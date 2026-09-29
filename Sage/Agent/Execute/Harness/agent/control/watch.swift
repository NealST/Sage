//
//  watch.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/watch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  When a ThreadManager holds the agent, status updates stream from
//  CodexThread. Without a manager, known registry identities emit one
//  inspect snapshot so existing mailbox tests stay one-shot. wait_agent
//  uses the same stream to wait for a final status.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func subscribeStatus(agentId: ThreadId) async throws -> AsyncStream<AgentInfo> {
        if let manager = try? runtime.upgradeThreadManager() {
            let thread = try await manager.getThread(agentId)
            let config = thread.configSnapshot()
            let metadata = getAgentMetadata(agentId) ?? AgentMetadata()
            return AsyncStream { continuation in
                let task = Task {
                    for await status in thread.subscribeStatus() {
                        if Task.isCancelled { break }
                        continuation.yield(
                            .loaded(
                                agent: LiveAgent(
                                    threadId: agentId,
                                    metadata: metadata,
                                    status: status
                                ),
                                config: config
                            )
                        )
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
        let snapshot = try await inspectAgent(agentId)
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    /// Wait until at least one target reaches a final status, matching rust
    /// `wait_agent`: already-final snapshots return immediately; otherwise
    /// race remaining watches until the first final status or `timeout`.
    public func waitForFinalStatuses(
        threadIds: [ThreadId],
        timeout: Duration
    ) async throws -> [(ThreadId, AgentStatus)] {
        var initialFinal: [(ThreadId, AgentStatus)] = []
        for threadId in threadIds {
            do {
                var updates = try await subscribeStatus(agentId: threadId).makeAsyncIterator()
                guard let initial = await updates.next() else {
                    throw CodexErr.internalAgentDied
                }
                let status = initial.status() ?? .notFound
                if isFinal(status) {
                    initialFinal.append((threadId, status))
                }
            } catch let err as CodexErr {
                if case .threadNotFound = err.detailsValue() {
                    initialFinal.append((threadId, .notFound))
                } else {
                    throw err
                }
            }
        }
        if !initialFinal.isEmpty {
            return initialFinal
        }
        return try await raceFinalStatuses(threadIds: threadIds, timeout: timeout)
    }

    private func raceFinalStatuses(
        threadIds: [ThreadId],
        timeout: Duration
    ) async throws -> [(ThreadId, AgentStatus)] {
        enum Race: Sendable {
            case finished(ThreadId, AgentStatus)
            case endedWithoutFinal
            case timedOut
            case cancelled
        }

        return await withTaskGroup(of: Race.self) { group in
            for threadId in threadIds {
                group.addTask {
                    if let result = await self.waitForFinalStatus(threadId) {
                        return .finished(result.0, result.1)
                    }
                    return .endedWithoutFinal
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return Task.isCancelled ? .cancelled : .timedOut
                } catch {
                    return .cancelled
                }
            }

            var results: [(ThreadId, AgentStatus)] = []
            var pendingWatches = threadIds.count
            while let race = await group.next() {
                switch race {
                case .finished(let threadId, let status):
                    results.append((threadId, status))
                    group.cancelAll()
                    while let extra = await group.next() {
                        if case .finished(let extraId, let extraStatus) = extra {
                            results.append((extraId, extraStatus))
                        }
                    }
                    return results
                case .endedWithoutFinal:
                    pendingWatches -= 1
                    if pendingWatches == 0 {
                        group.cancelAll()
                        while await group.next() != nil {}
                        return []
                    }
                case .timedOut:
                    group.cancelAll()
                    while let extra = await group.next() {
                        if case .finished(let extraId, let extraStatus) = extra {
                            results.append((extraId, extraStatus))
                        }
                    }
                    return results
                case .cancelled:
                    continue
                }
            }
            return results
        }
    }

    private func waitForFinalStatus(_ threadId: ThreadId) async -> (ThreadId, AgentStatus)? {
        if Task.isCancelled { return nil }
        do {
            for await snapshot in try await subscribeStatus(agentId: threadId) {
                if Task.isCancelled { return nil }
                let status = snapshot.status() ?? .notFound
                if isFinal(status) {
                    return (threadId, status)
                }
            }
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled { return nil }
        }
        if Task.isCancelled { return nil }
        let latest = await getStatus(threadId)
        return isFinal(latest) ? (threadId, latest) : nil
    }
}
