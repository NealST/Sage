//
//  mcp_runtime.swift
//  Sage
//
//  Port of codex-rs/core/src/session/mcp_runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `publishRefresh` consumes `reconnect_pending` and installs a new
//  immutable binding. Enabled servers keep their live connection when the
//  url is unchanged. A reconnect drops that set and opens fresh clients.
//  Servers that left the set are listed as closed.
//

import CodexCore
import CodexProtocol
import Foundation

/// One live client for a configured server. Reuse is object identity.
final class McpServerConnection: @unchecked Sendable {
    let server: String
    let url: String?

    init(server: String, url: String?) {
        self.server = server
        self.url = url
    }
}

struct McpConnectionPlan: Sendable {
    var fresh: Bool
    var opened: [String]
    /// Servers that had a live connection and are now disabled or gone.
    var closed: [String]
}

/// Immutable MCP snapshot. Steps keep the instance they captured.
final class PublishedMcpBinding: @unchecked Sendable {
    let id: UInt64
    let servers: [String: ConfiguredMcpServer]
    let approvalPolicy: CodexProtocol.AskForApproval
    let permissionProfile: PermissionProfile
    let tools: [McpVisibleTool]
    var connections: [String: McpServerConnection] = [:]

    init(
        id: UInt64,
        servers: [String: ConfiguredMcpServer],
        approvalPolicy: CodexProtocol.AskForApproval,
        permissionProfile: PermissionProfile,
        tools: [McpVisibleTool]
    ) {
        self.id = id
        self.servers = servers
        self.approvalPolicy = approvalPolicy
        self.permissionProfile = permissionProfile
        self.tools = tools
    }
}

final class SessionMcpRuntime: @unchecked Sendable {
    var dirty = false
    /// rust `reconnect_pending`. The next published refresh drops live connections.
    var reconnectPending = false
    /// rust `resource_cache_generation`. Incremented when catalogs must be reread.
    var resourceCacheGeneration: UInt64 = 0
    /// How many times publication has started, including one still inside `publishHook`.
    var publishAttempts: UInt64 = 0
    /// Completed publications.
    var publishCount: UInt64 = 0
    /// Completed publications that consumed a pending reconnect.
    var reconnectedPublishCount: UInt64 = 0
    /// Last completed publication consumed `reconnect_pending`.
    var lastPublishReconnected = false
    /// Test seam. Runs before the reconnect bit is consumed.
    var publishHook: (@Sendable () async -> Void)?
    /// Opens clients for `plan.opened`. A fresh plan replaces the previous set.
    var openConnections: (@Sendable (McpConnectionPlan) async -> Void)?
    /// rust `elicitation_router.auto_deny`. Requests accept an empty form
    /// without asking the user.
    var elicitationsAutoDeny = false
    /// rust `McpRuntime::resolve_elicitation` when the active turn has no waiter.
    var resolveElicitationFallback: (
        @Sendable (String, RequestId, ElicitationResponse) async throws -> Void
    )?
    /// Latest published binding. Nil until the first dirty refresh.
    private(set) var currentBinding: PublishedMcpBinding?
    private var liveConnections: [String: McpServerConnection] = [:]

    init() {}

    func markDirty() { dirty = true }

    /// rust `McpRuntime::reconnect_on_next_refresh`.
    func reconnectOnNextRefresh() { reconnectPending = true }

    /// rust `McpRuntime::invalidate_resource_caches`.
    func invalidateResourceCaches() {
        resourceCacheGeneration &+= 1
    }

    /// rust `McpRuntime::replace`. Installs `binding` and consumes reconnect.
    func publishRefresh(_ binding: PublishedMcpBinding) async {
        publishAttempts &+= 1
        if let publishHook {
            await publishHook()
        }
        let reconnected = reconnectPending
        reconnectPending = false
        let plan = installConnections(for: binding, fresh: reconnected)
        if let openConnections {
            await openConnections(plan)
        }
        dirty = false
        currentBinding = binding
        publishCount &+= 1
        if reconnected {
            reconnectedPublishCount &+= 1
        }
        lastPublishReconnected = reconnected
    }

    /// rust `McpConnectionSet::new`: reuse a client when reconnect was not
    /// requested and the server url is unchanged. Disabled and removed
    /// servers leave the set and are reported in `closed`.
    func installConnections(for binding: PublishedMcpBinding, fresh: Bool) -> McpConnectionPlan {
        let previous = liveConnections
        let reusable = fresh ? [:] : previous
        var next: [String: McpServerConnection] = [:]
        var opened: [String] = []
        for name in binding.servers.keys.sorted() {
            guard binding.servers[name]?.enabled == true else { continue }
            let url = binding.servers[name]?.url
            if let existing = reusable[name], existing.url == url {
                next[name] = existing
            } else {
                next[name] = McpServerConnection(server: name, url: url)
                opened.append(name)
            }
        }
        let closed = previous.keys.filter { next[$0] == nil }.sorted()
        liveConnections = next
        binding.connections = next
        return McpConnectionPlan(fresh: fresh, opened: opened, closed: closed)
    }
}
