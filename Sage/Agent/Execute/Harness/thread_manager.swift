//
//  thread_manager.swift
//  CodexCore
//
//  Port of codex-rs/core/src/thread_manager.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session, Config, agents, extensions, and AuthManager stay in later
//  phases / the Sage app. This file keeps the public snapshot types and a
//  Session-free manager shell so callers can compile against the facade.
//

import CodexHistory
import CodexProtocol
import Foundation

/// Represents a newly created Codex thread, including the first event
/// (which is `EventMsg.sessionConfigured`).
public struct NewThread: Sendable {
    public var threadId: ThreadId
    public var sessionConfigured: SessionConfiguredEvent

    public init(threadId: ThreadId, sessionConfigured: SessionConfiguredEvent) {
        self.threadId = threadId
        self.sessionConfigured = sessionConfigured
    }
}

public enum ForkSnapshot: Equatable, Sendable {
    /// Fork a committed prefix ending strictly before the nth user message.
    case truncateBeforeNthUserMessage(Int)
    /// Fork the current persisted history as if the source thread had been interrupted.
    case interrupted
}

extension ForkSnapshot: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .truncateBeforeNthUserMessage(value)
    }
}

public struct ThreadShutdownReport: Equatable, Sendable {
    public var completed: [ThreadId]
    public var submitFailed: [ThreadId]
    public var timedOut: [ThreadId]

    public init(
        completed: [ThreadId] = [],
        submitFailed: [ThreadId] = [],
        timedOut: [ThreadId] = []
    ) {
        self.completed = completed
        self.submitFailed = submitFailed
        self.timedOut = timedOut
    }
}

public struct StartThreadOptions: Sendable {
    public var model: String?
    public var cwd: String?
    public var source: SessionSource

    public init(model: String? = nil, cwd: String? = nil, source: SessionSource = .cli) {
        self.model = model
        self.cwd = cwd
        self.source = source
    }
}

/// Creates threads and keeps live handles. Session construction is deferred
/// until Phase 5 Session moves into CodexCore.
public final class ThreadManager: @unchecked Sendable {
    public init() {}
}

public func forkHistoryItems(
    _ items: [RolloutItem],
    snapshot: ForkSnapshot
) -> [RolloutItem] {
    switch snapshot {
    case .truncateBeforeNthUserMessage(let n):
        return truncateRolloutBeforeNthUserMessageFromStart(items, nFromStart: n)
    case .interrupted:
        return items
    }
}
