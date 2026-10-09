//
//  mcp_prewarm.swift
//  Sage
//
//  Port of codex-rs/core/src/session/mcp_prewarm.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `Op::RefreshMcpServers` asks the next refresh to reconnect and reread
//  resource catalogs. A bounded slot coalesces those requests. The worker
//  is detached from the caller. Each claimed dirty refresh snapshots the
//  current MCP servers, approval policy, and visible tools into a new
//  binding, then consumes `reconnect_pending`. An auth-generation change
//  marks the runtime dirty and publishes again. Enabled servers reuse a
//  live connection until a reconnect or a url change opens a new one.
//  Disabled or removed servers are disconnected after that connect.
//

import CodexAsyncUtils
import Foundation

private enum McpPrewarmWake {
    case request
    case auth
    case idle
    case closed
}

/// rust `async_channel::bounded(1)` plus `auth_change_receiver`. A second
/// request send while one is already queued is dropped. Auth is a generation
/// counter; the worker records the generation it has already seen.
final class McpPrewarmRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false
    private var authGeneration: UInt64 = 0
    private var closed = false
    private var waiters: [UUID: WakeWaiter] = [:]

    private final class WakeWaiter: @unchecked Sendable {
        let lock = NSLock()
        var continuation: CheckedContinuation<Void, Never>?
        var fired = false

        func fire() -> CheckedContinuation<Void, Never>? {
            lock.lock()
            defer { lock.unlock() }
            if fired { return nil }
            fired = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        func set(_ continuation: CheckedContinuation<Void, Never>) -> CheckedContinuation<Void, Never>? {
            lock.lock()
            defer { lock.unlock() }
            if fired { return continuation }
            self.continuation = continuation
            return nil
        }
    }

    var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending
    }

    var currentAuthGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return authGeneration
    }

    func trySend() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        pending = true
        let waiters = self.waiters
        self.waiters = [:]
        lock.unlock()
        for waiter in waiters.values {
            waiter.fire()?.resume()
        }
    }

    /// rust `auth_change_tx.send`. Does not itself mark the runtime dirty.
    func noteAuthChange() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        authGeneration &+= 1
        let waiters = self.waiters
        self.waiters = [:]
        lock.unlock()
        for waiter in waiters.values {
            waiter.fire()?.resume()
        }
    }

    /// Request wins over auth. `.idle` means the worker should wait.
    fileprivate func take(seenAuth: inout UInt64) -> McpPrewarmWake {
        lock.lock()
        defer { lock.unlock() }
        if closed { return .closed }
        if pending {
            pending = false
            return .request
        }
        if authGeneration != seenAuth {
            seenAuth = authGeneration
            return .auth
        }
        return .idle
    }

    fileprivate func wait(seenAuth: UInt64) async {
        let id = UUID()
        let waiter = WakeWaiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if closed || pending || authGeneration != seenAuth {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters[id] = waiter
                lock.unlock()
                waiter.set(continuation)?.resume()
            }
        } onCancel: {
            let removed = lock.withLock { waiters.removeValue(forKey: id) }
            (removed ?? waiter).fire()?.resume()
        }
    }

    func close() {
        lock.lock()
        closed = true
        pending = false
        let waiters = self.waiters
        self.waiters = [:]
        lock.unlock()
        for waiter in waiters.values {
            waiter.fire()?.resume()
        }
    }
}

extension Session {
    func prewarmMcp() async {}

    /// rust `refresh_mcp_servers`. Does not start a turn.
    func refreshMcpServers() {
        services.mcpRuntime.reconnectOnNextRefresh()
        requestMcpRuntimeRefresh()
    }

    /// rust `Session::request_mcp_runtime_refresh`.
    func requestMcpRuntimeRefresh() {
        services.mcpRuntime.invalidateResourceCaches()
        requestMcpRuntimeReprojection()
    }

    /// rust `Session::schedule_mcp_prewarm`.
    func scheduleMcpPrewarm() {
        mcpPrewarmRequests.trySend()
    }

    /// rust `AuthManager::auth_change_receiver` notify. The worker marks the
    /// runtime dirty and publishes; this does not reconnect or bump the
    /// resource-cache generation.
    func noteMcpAuthChanged() {
        mcpPrewarmRequests.noteAuthChange()
    }

    func markMcpRuntimeDirty() {
        mcpRefresh.invalidate()
        services.mcpRuntime.markDirty()
    }

    /// rust `Session::refresh_mcp_if_dirty`. Environment and auth comparisons
    /// stay out. A claimed dirty bit publishes a binding from the current config.
    func refreshMcpIfDirty() async {
        guard await mcpRefresh.acquire() else { return }
        defer { mcpRefresh.release() }
        while mcpRefresh.claim() {
            let binding = publishedMcpBinding()
            await services.mcpRuntime.publishRefresh(binding)
        }
    }

    /// Servers, approval authority, and the visible catalog at publish time.
    func publishedMcpBinding() -> PublishedMcpBinding {
        let config = state.sessionConfiguration.originalConfig
        let nextID = (services.mcpRuntime.currentBinding?.id ?? 0) &+ 1
        services.mcpBindingID = nextID
        return PublishedMcpBinding(
            id: nextID,
            servers: config.mcpServers,
            approvalPolicy: config.approvalPolicy,
            permissionProfile: config.permissions.permissionProfile,
            tools: services.mcpVisibleTools
        )
    }

    func startMcpPrewarmWorker() {
        guard mcpPrewarmTask == nil else { return }
        let requests = mcpPrewarmRequests
        let shutdown = mcpPrewarmShutdown
        let subscribedAuth = requests.currentAuthGeneration
        services.mcpRuntime.openConnections = { [weak self] plan in
            await self?.openPublishedMcpConnections(plan)
        }
        mcpPrewarmTask = Task.detached { [weak self] in
            var seenAuth = subscribedAuth
            while !shutdown.isCancelled {
                let wake = requests.take(seenAuth: &seenAuth)
                switch wake {
                case .closed:
                    return
                case .idle:
                    if shutdown.isCancelled { return }
                    await requests.wait(seenAuth: seenAuth)
                case .request:
                    guard !shutdown.isCancelled, let session = self else { return }
                    await session.refreshMcpIfDirty()
                case .auth:
                    guard !shutdown.isCancelled, let session = self else { return }
                    session.markMcpRuntimeDirty()
                    if shutdown.isCancelled { return }
                    await session.refreshMcpIfDirty()
                }
            }
        }
    }

    /// Fresh publish replaces clients. Any other newly opened server uses the
    /// ensure path, which leaves already-running clients in place. Servers
    /// that left the set are disconnected afterwards so a reconnect cannot
    /// start them again in the same publish.
    func openPublishedMcpConnections(_ plan: McpConnectionPlan) async {
        if plan.fresh, let reconnectMcp = services.reconnectMcp {
            await reconnectMcp()
        } else if !plan.opened.isEmpty {
            await services.ensureMcpConnected?()
        }
        if !plan.closed.isEmpty {
            await services.disconnectMcp?(plan.closed)
        }
    }

    func stopMcpPrewarmWorker() async {
        mcpPrewarmShutdown.cancel()
        mcpPrewarmRequests.close()
        mcpRefresh.close()
        let task = mcpPrewarmTask
        mcpPrewarmTask = nil
        await task?.value
    }
}
