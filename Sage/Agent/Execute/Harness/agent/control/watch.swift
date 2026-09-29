//
//  watch.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/watch.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Known registry identities emit one inspect snapshot. Live status
//  streams wait on ThreadManager / watch channels.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func subscribeStatus(agentId: ThreadId) async throws -> AsyncStream<AgentInfo> {
        let snapshot = try await inspectAgent(agentId)
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}
