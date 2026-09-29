//
//  execution.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/execution.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation
import os

public final class AgentExecutionLimiter: @unchecked Sendable {
    private struct State {
        var active: Int = 0
        var maxThreads: Int?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func initialize(_ maxThreads: Int) {
        lock.withLock { state in
            if state.maxThreads == nil {
                state.maxThreads = maxThreads
            }
        }
    }

    func maxThreads() -> Int {
        lock.withLock { $0.maxThreads ?? Int.max }
    }

    func hasCapacity() -> Bool {
        lock.withLock { $0.active < ($0.maxThreads ?? Int.max) }
    }

    func guardPermit() -> AgentExecutionGuard {
        lock.withLock { $0.active += 1 }
        return AgentExecutionGuard(permit: LocalExecutionPermit(limiter: self))
    }

    fileprivate func release() {
        lock.withLock { $0.active -= 1 }
    }
}

private final class LocalExecutionPermit {
    let limiter: AgentExecutionLimiter

    init(limiter: AgentExecutionLimiter) {
        self.limiter = limiter
    }

    deinit {
        limiter.release()
    }
}

func isExecutionLimited(
    _ multiAgentVersion: MultiAgentVersion,
    sessionSource: SessionSource
) -> Bool {
    if multiAgentVersion != .v2 { return false }
    if case .subAgent = sessionSource { return true }
    return false
}

extension LocalAgentControl {
    public func ensureExecutionCapacity(
        _ multiAgentVersion: MultiAgentVersion,
        sessionSource: SessionSource
    ) throws {
        if !isExecutionLimited(multiAgentVersion, sessionSource: sessionSource) {
            return
        }
        if runtime.agentExecutionLimiter.hasCapacity() {
            return
        }
        throw CodexErr.agentLimitReached(maxThreads: runtime.agentExecutionLimiter.maxThreads())
    }

    public func executionGuard(
        _ multiAgentVersion: MultiAgentVersion,
        sessionSource: SessionSource
    ) -> AgentExecutionGuard? {
        guard isExecutionLimited(multiAgentVersion, sessionSource: sessionSource) else {
            return nil
        }
        return runtime.agentExecutionLimiter.guardPermit()
    }
}
