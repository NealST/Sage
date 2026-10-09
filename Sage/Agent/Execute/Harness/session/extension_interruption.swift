//
//  extension_interruption.swift
//  Sage
//
//  Port of codex-rs/core/src/session/extension_interruption.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Aborts the named live turn only when that turn has no queued input.
//  Rust checks the turn-state queue and the mailbox. Swift also checks
//  the session queue, because a steered user message lands there instead
//  of on the turn. The decision is stored and the submission ack is
//  signaled before the abort runs. Agent-status `Interrupted` waits;
//  this session has no status watch. A closed reply channel waits.
//

import CodexProtocol
import Foundation

extension Session {
    /// rust `Session::interrupt_turn_if_no_pending_input`.
    func interruptTurnIfNoPendingInput(turnId: String, ack: SubmissionAck?) async {
        guard let turn = activeTurn,
              let task = turn.task,
              task.turnContext.subId == turnId
        else {
            lastInterruptIfNoPendingInput = false
            return
        }
        if !turn.turnState.pendingInput.isEmpty
            || inputQueue.hasSessionPendingItems()
            || inputQueue.hasPendingMailboxItems()
        {
            lastInterruptIfNoPendingInput = false
            return
        }
        lastInterruptIfNoPendingInput = true
        ack?.signal()
        await abortAllTasks(reason: .interrupted)
        await maybeStartTurnForPendingWork()
    }
}
