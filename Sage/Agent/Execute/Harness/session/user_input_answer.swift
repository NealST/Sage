//
//  user_input_answer.swift
//  Sage
//
//  Port of `request_user_input` / `notify_user_input_response` in
//  codex-rs/core/src/session/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A `request_user_input` call waits on the active turn, keyed by that
//  turn's id. `Op::UserInputAnswer` resumes that waiter and does not
//  start a turn. A missing waiter is ignored. A verified answer is
//  recorded when `guardian_approval` is enabled and history is thread-owned.
//

import CodexCore
import CodexProtocol
import Foundation

extension Session {
    /// rust `Session::request_user_input`.
    func requestUserInput(
        turnContext: TurnContext,
        callId: String,
        args: RequestUserInputArgs
    ) async -> AcceptedUserInputResponse? {
        let key = turnContext.subId
        let accepted: AcceptedUserInputResponse? = await withCheckedContinuation { continuation in
            if let turn = activeTurn {
                let previous = turn.turnState.insertPendingUserInput(
                    key: key,
                    continuation: continuation
                )
                previous?.resume(returning: nil)
            } else {
                continuation.resume(returning: nil)
            }
            sendEvent(
                turnContext,
                .requestUserInput(
                    RequestUserInputEvent(
                        callId: callId,
                        turnId: turnContext.subId,
                        questions: args.questions,
                        isBlocking: args.isBlocking,
                        autoResolutionMs: args.autoResolutionMs
                    )
                )
            )
        }
        if let accepted {
            await recordRetainedVerifiedAnswer(
                turnContext: turnContext,
                callId: callId,
                questions: args.questions,
                response: accepted.response,
                acceptanceOrder: accepted.acceptanceOrder
            )
        }
        return accepted
    }

    /// rust `Session::notify_user_input_response`.
    func notifyUserInputResponse(id: String, response: RequestUserInputResponse) {
        guard let continuation = activeTurn?.turnState.removePendingUserInput(key: id) else {
            return
        }
        continuation.resume(
            returning: AcceptedUserInputResponse(
                response: response,
                acceptanceOrder: reserveUserInputOrder()
            )
        )
    }

    /// rust `reserve_user_input_order`. Legacy mode reserves nothing.
    func reserveUserInputOrder() -> UInt64? {
        if state.history.guardianReviewMode == .legacy {
            return nil
        }
        let order = nextUserInputOrder
        nextUserInputOrder = order == .max ? order : order + 1
        return order
    }
}
