//
//  inspection.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/inspection.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Known registry metadata is inspectable without a runtime. Agents with
//  mailbox status report `.loaded`; others stay `.unloaded` until
//  ThreadManager can supply a live snapshot.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func inspectAgent(_ threadId: ThreadId) async throws -> AgentInfo {
        let metadata = try runtime.ensureAgentKnown(threadId)
        guard runtime.delivery.status(threadId) != nil else {
            return .unloaded(metadata)
        }
        return .loaded(
            agent: liveSnapshot(threadId: threadId, metadata: metadata),
            config: ThreadConfigSnapshot(model: "", sessionSource: .unknown)
        )
    }
}
