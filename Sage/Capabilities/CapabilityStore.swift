//
//  CapabilityStore.swift
//  Sage
//

import AppKit
import Foundation

@MainActor
@Observable
final class CapabilityStore {
    private(set) var skills: [SkillRecord] = []
    private(set) var mcpServers: [MCPServerConfig] = []
    private(set) var mcpTools: [MCPToolInfo] = []

    private let store = MCPConfigStore()
    private var clients: [String: MCPStdioClient] = [:]
    private var reconnectTasks: [String: Task<Void, Never>] = [:]

    /// Maximum consecutive reconnect attempts before giving up.
    private static let maxReconnectAttempts = 3
    /// Base delay for exponential backoff (doubles each attempt).
    private static let reconnectBaseDelay: TimeInterval = 1.0

    var enabledSkills: [SkillRecord] {
        skills.filter(\.enabled)
    }

    func bootstrap() async {
        await reloadSkills()
        await reloadMCPConfigs()
        await reconnectEnabledServers()
    }

    // MARK: - Skills

    func reloadSkills() async {
        let scanned = SkillRegistry.scanDefaultLocations()
        let state = await store.loadSkillState()
        skills = scanned.map { skill in
            var copy = skill
            if let enabled = state[skill.name] {
                copy.enabled = enabled
            }
            return copy
        }
    }

    func setSkillEnabled(_ name: String, enabled: Bool) {
        guard let index = skills.firstIndex(where: { $0.name == name }) else { return }
        skills[index].enabled = enabled
        persistSkillState()
    }

    func openSkillsFolder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sage/Skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// Result of progressive skill activation.
    struct SkillAppendixResult: Sendable {
        /// The text to append to the system prompt.
        let text: String
        /// Whether the cloud model needs the `load_skill` tool to fetch skill bodies.
        let needsLoadSkillTool: Bool
    }

    /// Progressive skill activation:
    /// - Local model available → returns full body of matched skills (no tool needed)
    /// - Local model unavailable → returns catalog only (name + description);
    ///   the cloud model uses `load_skill` tool to fetch full content on demand
    func skillsPromptAppendix(for userMessage: String) async -> SkillAppendixResult {
        let active = enabledSkills
        guard !active.isEmpty else { return SkillAppendixResult(text: "", needsLoadSkillTool: false) }

        let result = await skillMatcher.match(
            userMessage: userMessage,
            skills: active
        )

        switch result {
        case .resolved(let names):
            let matched = active.filter { names.contains($0.name) }
            guard !matched.isEmpty else {
                return SkillAppendixResult(text: "", needsLoadSkillTool: false)
            }
            var lines: [String] = ["", "## Active Skills", "Follow these skills when relevant:"]
            for skill in matched {
                lines.append("### \(skill.name)")
                lines.append(skill.description)
                let body = SkillRegistry.readBody(for: skill, limit: 2_500)
                if !body.isEmpty {
                    lines.append(body)
                }
                lines.append("")
            }
            return SkillAppendixResult(text: lines.joined(separator: "\n"), needsLoadSkillTool: false)

        case .deferred:
            var lines: [String] = [
                "",
                "## Available Skills",
                "The following skills are available. Use the `load_skill` tool to load a skill's full content when relevant to the user's request.",
                ""
            ]
            for skill in active {
                lines.append("- **\(skill.name)**: \(skill.description)")
            }
            lines.append("")
            return SkillAppendixResult(text: lines.joined(separator: "\n"), needsLoadSkillTool: true)
        }
    }

    /// Loads the full body of a skill by name. Used by the `load_skill` tool.
    func loadSkillBody(name: String) -> String? {
        guard let skill = skills.first(where: { $0.name == name && $0.enabled }) else {
            return nil
        }
        return SkillRegistry.readBody(for: skill, limit: 4_000)
    }

    private let skillMatcher = SkillMatcher()

    // MARK: - MCP

    func reloadMCPConfigs() async {
        var loaded = await store.loadServers()
        loaded = loaded.map { server in
            var copy = server
            if let existing = mcpServers.first(where: { $0.id == server.id }) {
                copy.status = server.enabled ? existing.status : .disabled
                copy.statusMessage = existing.statusMessage
                copy.toolCount = existing.toolCount
            } else {
                copy.status = server.enabled ? .disconnected : .disabled
            }
            return copy
        }
        mcpServers = loaded
    }

    func addMCPServer(_ server: MCPServerConfig) {
        mcpServers.append(server)
        persistMCP()
        if server.enabled {
            Task { await connect(serverID: server.id) }
        }
    }

    func updateMCPServer(_ server: MCPServerConfig) {
        guard let index = mcpServers.firstIndex(where: { $0.id == server.id }) else { return }
        let wasEnabled = mcpServers[index].enabled
        mcpServers[index].command = server.command
        mcpServers[index].args = server.args
        mcpServers[index].env = server.env
        mcpServers[index].name = server.name
        mcpServers[index].enabled = server.enabled
        persistMCP()
        if server.enabled {
            Task { await connect(serverID: server.id) }
        } else if wasEnabled {
            Task { await disconnect(serverID: server.id) }
        }
    }

    func deleteMCPServer(_ id: String) {
        reconnectTasks[id]?.cancel()
        reconnectTasks[id] = nil
        Task { await disconnect(serverID: id) }
        mcpServers.removeAll { $0.id == id }
        mcpTools.removeAll { $0.serverID == id }
        persistMCP()
    }

    func setMCPEnabled(_ id: String, enabled: Bool) {
        guard let index = mcpServers.firstIndex(where: { $0.id == id }) else { return }
        mcpServers[index].enabled = enabled
        if enabled {
            mcpServers[index].status = .disconnected
            mcpServers[index].reconnectAttempts = 0
            persistMCP()
            Task { await connect(serverID: id) }
        } else {
            reconnectTasks[id]?.cancel()
            reconnectTasks[id] = nil
            mcpServers[index].status = .disabled
            mcpServers[index].statusMessage = nil
            mcpServers[index].toolCount = 0
            mcpServers[index].reconnectAttempts = 0
            mcpTools.removeAll { $0.serverID == id }
            persistMCP()
            Task { await disconnect(serverID: id) }
        }
    }

    func connect(serverID: String) async {
        guard let index = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        guard mcpServers[index].enabled else { return }

        // Cancel any pending reconnect for this server.
        reconnectTasks[serverID]?.cancel()
        reconnectTasks[serverID] = nil

        mcpServers[index].status = .connecting
        mcpServers[index].statusMessage = nil

        await disconnect(serverID: serverID)

        let config = mcpServers[index]
        let client = MCPStdioClient(config: config)

        // Wire up process exit callback for auto-reconnect.
        await client.setOnProcessExit { [weak self] exitedServerID in
            await self?.handleServerProcessExit(serverID: exitedServerID)
        }

        clients[serverID] = client

        do {
            let tools = try await withThrowingTaskGroup(of: [MCPToolInfo].self) { group in
                group.addTask { try await client.connect() }
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    throw MCPStdioClient.ClientError.remote("Connection timed out")
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            guard let idx = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
            mcpServers[idx].status = .connected
            mcpServers[idx].toolCount = tools.count
            mcpServers[idx].statusMessage = nil
            mcpServers[idx].reconnectAttempts = 0
            mcpServers[idx].recentLogs = await client.stderrLog
            mcpTools.removeAll { $0.serverID == serverID }
            mcpTools.append(contentsOf: tools)
        } catch {
            guard let idx = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
            let stderrLines = await client.stderrLog
            mcpServers[idx].status = .error
            mcpServers[idx].statusMessage = stderrLines.last ?? error.localizedDescription
            mcpServers[idx].toolCount = 0
            mcpServers[idx].recentLogs = stderrLines
            mcpTools.removeAll { $0.serverID == serverID }
            clients[serverID] = nil
        }
    }

    func reconnectEnabledServers() async {
        for server in mcpServers where server.enabled {
            await connect(serverID: server.id)
        }
    }

    /// Manually retry a failed server (resets reconnect counter).
    func retryServer(_ serverID: String) {
        guard let index = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        mcpServers[index].reconnectAttempts = 0
        mcpServers[index].statusMessage = nil
        Task { await connect(serverID: serverID) }
    }

    /// Called when a server process exits unexpectedly. Triggers auto-reconnect with backoff.
    private func handleServerProcessExit(serverID: String) async {
        guard let index = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        guard mcpServers[index].enabled else { return }

        // Sync stderr logs from the client before it's removed.
        // The client reference is grabbed first; after the await the array may have shifted.
        let exitedClient = clients[serverID]
        if let exitedClient {
            let logs = await exitedClient.stderrLog
            if let idx = mcpServers.firstIndex(where: { $0.id == serverID }) {
                mcpServers[idx].recentLogs = logs
            }
        }

        // If a new client was installed during the await (manual reconnect raced us),
        // don't tear it down — only remove if it's still the crashed client.
        if let current = clients[serverID], current === exitedClient {
            clients[serverID] = nil
        } else if exitedClient == nil {
            clients[serverID] = nil
        }
        mcpTools.removeAll { $0.serverID == serverID }

        // Re-fetch index after the await — array may have mutated.
        guard let idx = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        guard mcpServers[idx].enabled else { return }

        let attempts = mcpServers[idx].reconnectAttempts
        if attempts >= Self.maxReconnectAttempts {
            mcpServers[idx].status = .error
            mcpServers[idx].statusMessage = "Process exited — reconnect failed after \(attempts) attempts"
            return
        }

        mcpServers[idx].status = .reconnecting
        mcpServers[idx].reconnectAttempts = attempts + 1
        mcpServers[idx].statusMessage = "Reconnecting (attempt \(attempts + 1)/\(Self.maxReconnectAttempts))…"

        let baseDelay = Self.reconnectBaseDelay * pow(2.0, Double(attempts))
        let jitter = Double.random(in: 0...(baseDelay * 0.3))
        let delay = baseDelay + jitter
        reconnectTasks[serverID] = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await connect(serverID: serverID)
        }
    }

    func callMCPTool(qualifiedName: String, argumentsJSON: String) async throws -> String {
        guard qualifiedName.hasPrefix("mcp__") else {
            throw MCPStdioClient.ClientError.invalidResponse("Not an MCP tool")
        }
        let rest = String(qualifiedName.dropFirst(5))
        guard let sep = rest.range(of: "__") else {
            throw MCPStdioClient.ClientError.invalidResponse("Malformed MCP tool name")
        }
        let serverName = String(rest[..<sep.lowerBound])
        let toolName = String(rest[sep.upperBound...])
        guard let server = mcpServers.first(where: { $0.name == serverName && $0.enabled }),
              let client = clients[server.id]
        else {
            throw MCPStdioClient.ClientError.notRunning
        }
        return try await client.callTool(name: toolName, argumentsJSON: argumentsJSON)
    }

    func mcpToolDefinitions() -> [ToolDefinition] {
        mcpTools.map { tool in
            ToolDefinition(
                name: tool.qualifiedName,
                description: "[\(tool.serverName)] \(tool.description)",
                parameters: tool.inputSchema
            )
        }
    }

    private func disconnect(serverID: String) async {
        reconnectTasks[serverID]?.cancel()
        reconnectTasks[serverID] = nil
        if let client = clients.removeValue(forKey: serverID) {
            await client.disconnect()
        }
    }

    private func persistMCP() {
        let snapshot = mcpServers
        Task {
            await store.saveServers(snapshot)
        }
    }

    private func persistSkillState() {
        var map: [String: Bool] = [:]
        for skill in skills {
            map[skill.name] = skill.enabled
        }
        Task {
            await store.saveSkillState(map)
        }
    }
}
