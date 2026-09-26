//
//  tasks_lifecycle.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/lifecycle.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Extension contributors wait for Phase 9. Session still records start/stop.
//

import CodexProtocol
import Foundation

enum TurnStartPhase: Equatable, Sendable {
    case regularTaskStart
    case reviewTaskStart
    case compactTaskStart
}

enum ThreadIdleCause: Equatable, Sendable {
    case completed
    case interrupted
}

extension Session {
    func emitTurnStartLifecycle(
        _ turnContext: TurnContext,
        tokenUsageAtTurnStart: TokenUsage?,
        phase: TurnStartPhase
    ) async {
        _ = tokenUsageAtTurnStart
        _ = phase
        _ = turnContext
    }

    func emitTurnStopLifecycle() async {}

    func emitThreadIdleLifecycleIfIdle(_ cause: ThreadIdleCause) async {
        if activeTurn != nil { return }
        _ = cause
    }

    func emitTurnAbortLifecycle(_ reason: String) async {
        _ = reason
    }

    func emitTurnErrorLifecycle(_ turnContext: TurnContext, error: String) async {
        _ = turnContext
        _ = error
    }
}
