//
//  patch_approval.swift
//  Sage
//
//  Port of `request_patch_approval` in codex-rs/core/src/session/mod.rs and
//  `patch_approval` in codex-rs/core/src/session/handlers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A patch approval waits on the active turn, keyed by tool call id, in
//  the same map as command approvals. `Op::PatchApproval` resumes that
//  waiter and does not start a turn. Abort interrupts the active turn
//  instead of delivering a decision. A dropped waiter returns abort.
//

import CodexProtocol
import Foundation

extension Session {
    /// rust `Session::request_patch_approval`.
    func requestPatchApproval(
        turnContext: TurnContext,
        callId: String,
        changes: [String: FileChange],
        reason: String?,
        grantRoot: String?
    ) async -> CodexProtocol.ReviewDecision {
        let replaced = ReplacedApproval()
        let decision: CodexProtocol.ReviewDecision = await withCheckedContinuation { continuation in
            let waiter = ApprovalDecision(continuation)
            let event = ApplyPatchApprovalRequestEvent(
                callId: callId,
                turnId: turnContext.subId,
                startedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                changes: changes,
                reason: reason,
                grantRoot: grantRoot
            )
            if let turn = activeTurn {
                replaced.decision = turn.turnState.insertPendingApproval(
                    key: callId, decision: waiter)
                sendEvent(turnContext, .applyPatchApprovalRequest(event))
            } else {
                sendEvent(turnContext, .applyPatchApprovalRequest(event))
                waiter.resume(.abort)
            }
        }
        replaced.decision?.resume(.abort)
        return decision
    }

    /// rust `patch_approval`.
    func handlePatchApproval(id: String, decision: CodexProtocol.ReviewDecision) async {
        if case .abort = decision {
            await interruptTask()
        } else {
            notifyApproval(id: id, decision: decision)
        }
    }
}
