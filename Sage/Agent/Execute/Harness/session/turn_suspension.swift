//
//  turn_suspension.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn_suspension.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Stops the unfinished regular root turn without `TurnAborted` or
//  `TurnComplete`, so another worker can recover that turn id. Review
//  and compact tasks are refused. A live descendant count above one is
//  refused. The turn is removed before runtime shutdown, so shutdown
//  cannot record a terminal turn event. Rollout flush and writer close
//  wait; this session has no live rollout writer.
//

import CodexAsyncUtils
import CodexProtocol
import Foundation

extension Session {
    /// rust `suspend_turn_and_shutdown`. Returns whether the submission loop exits.
    func suspendTurnAndShutdown(submissionId: String) async -> Bool {
        if state.sessionConfiguration.sessionSource.isNonRootAgent() {
            lastSuspendTurnOutcome = nil
            lastSuspendTurnError = "turn suspension requires the owning root thread"
            return false
        }
        guard let turn = activeTurn, let task = turn.task else {
            lastSuspendTurnError = nil
            lastSuspendTurnOutcome = .notActive
            return false
        }
        if task.kind != .regular {
            lastSuspendTurnError = nil
            lastSuspendTurnOutcome = .unsupportedTask
            return false
        }
        if services.liveAgentSubtreeCount > 1 {
            lastSuspendTurnError = nil
            lastSuspendTurnOutcome = .hasLiveDescendants
            return false
        }
        let turnId = task.turnContext.subId
        activeTurn = nil
        task.cancellationToken?.cancel()
        task.done = true
        inputQueue.clearPending(turn)
        await finishShutdown(submissionId: submissionId)
        lastSuspendTurnError = nil
        lastSuspendTurnOutcome = .suspended(turnId: turnId)
        return true
    }
}
