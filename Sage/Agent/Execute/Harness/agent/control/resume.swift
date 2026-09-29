//
//  resume.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/resume.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Registered agents rematerialize from mailbox status. Closed threads
//  and rollout restore still wait on ThreadManager.
//

import CodexProtocol
import Foundation

extension LocalAgentControl {
    public func resumeAgent(
        threadId: ThreadId,
        source: SessionSource
    ) async throws -> (LiveAgent, ThreadConfigSnapshot) {
        let metadata = try runtime.ensureAgentKnown(threadId)
        if runtime.delivery.status(threadId) == nil {
            runtime.delivery.setStatus(threadId, .pendingInit)
        }
        return (
            liveSnapshot(threadId: threadId, metadata: metadata),
            ThreadConfigSnapshot(
                model: "",
                sessionSource: source,
                parentThreadId: source.parentThreadId()
            )
        )
    }
}
