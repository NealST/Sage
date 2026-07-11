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

    func skillsPromptAppendix() -> String {
        let active = enabledSkills
        guard !active.isEmpty else { return "" }
        var lines: [String] = ["", "## Active Skills", "Follow these skills when relevant:"]
        for skill in active {
            lines.append("### \(skill.name)")
            lines.append(skill.description)
            let body = SkillRegistry.readBody(for: skill, limit: 2_500)
            if !body.isEmpty {
                lines.append(body)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

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
            persistMCP()
            Task { await connect(serverID: id) }
        } else {
            mcpServers[index].status = .disabled
            mcpServers[index].statusMessage = nil
            mcpServers[index].toolCount = 0
            mcpTools.removeAll { $0.serverID == id }
            persistMCP()
            Task { await disconnect(serverID: id) }
        }
    }

    func connect(serverID: String) async {
        guard let index = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        guard mcpServers[index].enabled else { return }

        mcpServers[index].status = .connecting
        mcpServers[index].statusMessage = nil

        await disconnect(serverID: serverID)

        let config = mcpServers[index]
        let client = MCPStdioClient(config: config)
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
            mcpTools.removeAll { $0.serverID == serverID }
            mcpTools.append(contentsOf: tools)
        } catch {
            guard let idx = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
            mcpServers[idx].status = .error
            mcpServers[idx].statusMessage = error.localizedDescription
            mcpServers[idx].toolCount = 0
            mcpTools.removeAll { $0.serverID == serverID }
            clients[serverID] = nil
        }
    }

    func reconnectEnabledServers() async {
        for server in mcpServers where server.enabled {
            await connect(serverID: server.id)
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
