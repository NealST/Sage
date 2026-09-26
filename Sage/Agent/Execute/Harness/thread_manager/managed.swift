//
//  managed.swift
//  CodexCore
//
//  Port of codex-rs/core/src/thread_manager/managed.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Live-thread bookkeeping without Session / AgentControl.
//

import CodexProtocol
import Foundation

struct ManagedThread: Sendable {
    var threadId: ThreadId
    var startedAt: Date

    init(threadId: ThreadId, startedAt: Date = Date()) {
        self.threadId = threadId
        self.startedAt = startedAt
    }
}
