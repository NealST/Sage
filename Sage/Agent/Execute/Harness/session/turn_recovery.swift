//
//  turn_recovery.swift
//  Sage
//
//  Port of `handle_recovery` in codex-rs/core/src/session/turn_input.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resumes an interrupted regular turn only when the thread is idle.
//  The recovered turn keeps the caller's turn id, forces `turn_trigger`
//  to `retry`, and samples with no new user message. Thread settings
//  apply only after that admission. A pending trigger-turn mailbox or a
//  running task rejects the request and leaves settings unchanged.
//  Host drain admission stays on ThreadSession.
//

import CodexCore
import CodexProtocol
import Foundation

extension Session {
    /// rust `turn_input::handle_recovery`.
    func recoverTurn(_ request: RecoverTurnRequest) async {
        if inputQueue.hasTriggerTurnMailboxItems() {
            lastTurnInputError = nil
            lastTurnInputSubmission = .notSubmitted(reason: .pendingTriggerTurn)
            return
        }
        if hasRunningTask {
            lastTurnInputError = nil
            lastTurnInputSubmission = .notSubmitted(reason: .notIdle)
            return
        }
        if !request.threadSettings.isEmpty {
            do {
                try applyThreadSettingsOverrides(request.threadSettings)
            } catch let error as ThreadSettingsOverrideError {
                lastTurnInputSubmission = nil
                lastTurnInputError = "invalid thread settings override: \(error.message)"
                return
            } catch {
                lastTurnInputSubmission = nil
                lastTurnInputError = "invalid thread settings override: \(error)"
                return
            }
        }
        let start = TurnStartOptions(
            turnTrigger: "retry",
            rootTurnId: referenceRootTurnId(matching: request.turnId),
            cyberAccessProgram: request.cyberAccessProgram
        )
        let turn = newTurnContext(
            subId: request.turnId,
            options: NewTurnContextOptions(start: start)
        )
        lastStartedTurnContext = turn
        lastStartedTurnId = turn.subId
        startDetachedTask(RegularSessionTask(), turnContext: turn, input: [])
        lastTurnInputError = nil
        lastTurnInputSubmission = .started(turnId: request.turnId)
    }

    /// rust `reference_context_item` root id, copied only for the same turn.
    func referenceRootTurnId(matching turnId: String) -> String? {
        guard let item = state.history.referenceContextItemValue(), item.turnId == turnId else {
            return nil
        }
        return item.rootTurnId
    }
}
