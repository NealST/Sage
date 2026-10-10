//
//  submission.swift
//  Sage
//
//  Port of codex-rs/core/src/session/submission.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SessionOp is the subset the app-target Session loop dispatches.
//  `review` starts a review turn from a resolved ReviewRequest.
//  `threadSettings` updates session configuration without starting a turn.
//  `turnSettings` updates only the named running turn.
//  `interruptIfNoPendingInput` aborts that turn only when nothing is queued for it.
//  `recoverTurn` resumes an interrupted regular turn when the thread is idle.
//  `suspendTurnAndShutdown` stops the unfinished root turn without a terminal event.
//  `userInputAnswer` resumes a waiting `request_user_input` without starting a turn.
//  `requestPermissionsResponse` resumes a waiting `request_permissions` without starting a turn.
//  `dynamicToolResponse` resumes a waiting dynamic tool call without starting a turn.
//  `execApproval` resumes a waiting command approval. Abort interrupts the turn.
//  `patchApproval` resumes a waiting patch approval. Abort interrupts the turn.
//  `refreshMcpServers` asks the next MCP refresh to reconnect, without starting a turn.
//  `reloadUserConfig` reloads the user config layer without starting a turn.
//  `cleanBackgroundTerminals` stops this thread's background terminals without starting a turn.
//  `resolveElicitation` resumes a waiting MCP elicitation without starting a turn.
//  `approveGuardianDeniedAction` records one approved retry of a denied action
//  without starting a turn.
//

import CodexProtocol
import Foundation

enum SessionOp: Equatable, Sendable {
    case interrupt
    /// `Op::InterruptIfNoPendingInput`. Aborts the named turn only when it has
    /// no queued input. The decision is `lastInterruptIfNoPendingInput`.
    case interruptIfNoPendingInput(turnId: String)
    case shutdown
    /// `Op::SuspendTurnAndShutdown`. Cancels the regular root turn without
    /// `TurnAborted` or `TurnComplete`, then shuts the submission loop.
    case suspendTurnAndShutdown
    case userInput(SessionTurnInput)
    case interAgent(InterAgentCommunication)
    case compact
    case review(ReviewRequest)
    /// `Op::ThreadSettings`. Updates session configuration for later turns.
    case threadSettings(ThreadSettingsOverrides)
    /// `Op::TurnSettings`. Updates the named live turn's next step only.
    case turnSettings(turnId: String, update: TurnSettingsUpdate)
    /// `Op::RecoverTurn`. Resumes sampling for an interrupted regular turn.
    case recoverTurn(RecoverTurnRequest)
    /// `Op::UserInputAnswer`. `id` is the waiting turn id, not the tool call id.
    case userInputAnswer(id: String, response: RequestUserInputResponse)
    /// `Op::RequestPermissionsResponse`. `id` is the tool call id.
    case requestPermissionsResponse(id: String, response: RequestPermissionsResponse)
    /// `Op::DynamicToolResponse`. `id` is the tool call id.
    case dynamicToolResponse(id: String, response: DynamicToolResponse)
    /// `Op::ExecApproval`. `id` is the approval id, or the tool call id when
    /// the request did not set one. Abort interrupts the active turn.
    case execApproval(id: String, turnId: String?, decision: CodexProtocol.ReviewDecision)
    /// `Op::PatchApproval`. `id` is the tool call id. Abort interrupts the active turn.
    case patchApproval(id: String, decision: CodexProtocol.ReviewDecision)
    /// `Op::RefreshMcpServers`. Marks servers to reconnect on the next refresh.
    case refreshMcpServers
    /// `Op::ReloadUserConfig`. Reloads the user config layer for this session.
    case reloadUserConfig
    /// `Op::CleanBackgroundTerminals`. Stops this thread's background terminals.
    case cleanBackgroundTerminals
    /// `Op::ResolveElicitation`. Resumes a waiting MCP elicitation.
    /// Accept with no content sends an empty object. Decline and cancel drop content.
    case resolveElicitation(
        serverName: String,
        requestId: RequestId,
        decision: ElicitationAction,
        content: CodexProtocol.JSONValue?,
        meta: CodexProtocol.JSONValue?
    )
    /// `Op::ApproveGuardianDeniedAction`. Injects the approved action when
    /// the assessment was denied. Other statuses are ignored.
    case approveGuardianDeniedAction(GuardianAssessmentEvent)
}

final class SubmissionAck: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func signal() {
        lock.lock()
        fired = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}

struct Submission: Sendable {
    var id: String
    var op: SessionOp
    var parentTurnId: String?
    var rootTurnId: String?
    var startOptions: TurnStartOptions
    var ack: SubmissionAck?

    init(
        id: String,
        op: SessionOp,
        parentTurnId: String? = nil,
        rootTurnId: String? = nil,
        startOptions: TurnStartOptions = TurnStartOptions(),
        ack: SubmissionAck? = nil
    ) {
        self.id = id
        self.op = op
        self.parentTurnId = parentTurnId
        self.rootTurnId = rootTurnId
        self.startOptions = startOptions
        self.ack = ack
    }
}
