//
//  CapabilityStore.swift
//  Sage
//
//  Shared MCP hub (connections + tool defs). Skills live in SkillCatalog.
//

import Foundation

@MainActor
@Observable
final class CapabilityStore {
    private(set) var mcpServers: [MCPServerConfig] = []
    private(set) var mcpTools: [MCPToolInfo] = []

    private let store: MCPConfigStore
    var clients: [String: MCPStdioClient] = [:]
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    /// Per-server serial queue so rapid enable/disable/delete cannot interleave connect/disconnect.
    private var serverOperations: [String: Task<Void, Never>] = [:]

    private static let maxReconnectAttempts = 3
    private static let reconnectBaseDelay: TimeInterval = 1.0

    init(store: MCPConfigStore = MCPConfigStore()) {
        self.store = store
    }

    func bootstrap() async {
        await reloadMCPConfigs()
        await reconnectEnabledServers()
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
            enqueueServerOperation(serverID: server.id) { [weak self] in
                await self?.connect(serverID: server.id)
            }
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
            enqueueServerOperation(serverID: server.id) { [weak self] in
                await self?.connect(serverID: server.id)
            }
        } else if wasEnabled {
            enqueueServerOperation(serverID: server.id) { [weak self] in
                await self?.disconnect(serverID: server.id)
            }
        }
    }

    func deleteMCPServer(_ id: String) {
        reconnectTasks[id]?.cancel()
        reconnectTasks[id] = nil
        mcpServers.removeAll { $0.id == id }
        mcpTools.removeAll { $0.serverID == id }
        persistMCP()
        enqueueServerOperation(serverID: id) { [weak self] in
            await self?.disconnect(serverID: id)
        }
    }

    func setMCPEnabled(_ id: String, enabled: Bool) {
        guard let index = mcpServers.firstIndex(where: { $0.id == id }) else { return }
        mcpServers[index].enabled = enabled
        if enabled {
            mcpServers[index].status = .disconnected
            mcpServers[index].reconnectAttempts = 0
            persistMCP()
            enqueueServerOperation(serverID: id) { [weak self] in
                await self?.connect(serverID: id)
            }
        } else {
            reconnectTasks[id]?.cancel()
            reconnectTasks[id] = nil
            mcpServers[index].status = .disabled
            mcpServers[index].statusMessage = nil
            mcpServers[index].toolCount = 0
            mcpServers[index].reconnectAttempts = 0
            mcpTools.removeAll { $0.serverID == id }
            persistMCP()
            enqueueServerOperation(serverID: id) { [weak self] in
                await self?.disconnect(serverID: id)
            }
        }
    }

    func connect(serverID: String, writableRoots: [URL] = []) async {
        guard let index = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        guard mcpServers[index].enabled else { return }

        reconnectTasks[serverID]?.cancel()
        reconnectTasks[serverID] = nil

        mcpServers[index].status = .connecting
        mcpServers[index].statusMessage = nil

        await disconnect(serverID: serverID)

        guard let stillIndexed = mcpServers.firstIndex(where: { $0.id == serverID }),
              mcpServers[stillIndexed].enabled
        else { return }

        let config = mcpServers[stillIndexed]
        let client = MCPStdioClient(config: config, writableRoots: writableRoots)

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
                guard let result = try await group.next() else {
                    throw CancellationError()
                }
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

    func retryServer(_ serverID: String) {
        guard let index = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        mcpServers[index].reconnectAttempts = 0
        mcpServers[index].statusMessage = nil
        enqueueServerOperation(serverID: serverID) { [weak self] in
            await self?.connect(serverID: serverID)
        }
    }

    private func handleServerProcessExit(serverID: String) async {
        guard let index = mcpServers.firstIndex(where: { $0.id == serverID }) else { return }
        guard mcpServers[index].enabled else { return }

        let exitedClient = clients[serverID]
        if let exitedClient {
            let logs = await exitedClient.stderrLog
            if let idx = mcpServers.firstIndex(where: { $0.id == serverID }) {
                mcpServers[idx].recentLogs = logs
            }
        }

        if let current = clients[serverID], current === exitedClient {
            clients[serverID] = nil
        } else if exitedClient == nil {
            clients[serverID] = nil
        }
        mcpTools.removeAll { $0.serverID == serverID }

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
        reconnectTasks[serverID] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self.enqueueServerOperation(serverID: serverID) {
                await self.connect(serverID: serverID)
            }.value
        }
    }

    /// Chains work behind any in-flight op for the same server id.
    @discardableResult
    private func enqueueServerOperation(
        serverID: String,
        _ body: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let previous = serverOperations[serverID]
        let task = Task { @MainActor in
            await previous?.value
            await body()
        }
        serverOperations[serverID] = task
        return task
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
}
