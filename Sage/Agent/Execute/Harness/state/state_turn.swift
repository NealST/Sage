//
//  state_turn.swift
//  Sage
//
//  Port of codex-rs/core/src/state/turn.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Tokio oneshot waiters become CheckedContinuation. RunningTask holds
//  a SessionTask box instead of AbortOnDropHandle / OTel guards.
//

import CodexProtocol
import CodexSandboxing
import Foundation

enum MailboxDeliveryPhase: Equatable, Sendable {
    case currentTurn
    case nextTurn
}

enum TaskKind: Equatable, Sendable {
    case regular
    case review
    case compact
}

struct AcceptedUserInputResponse: Sendable {
    var response: RequestUserInputResponse
    var acceptanceOrder: UInt64

    init(response: RequestUserInputResponse, acceptanceOrder: UInt64) {
        self.response = response
        self.acceptanceOrder = acceptanceOrder
    }
}

struct PendingRequestPermissions: Sendable {
    var requestedPermissions: RequestPermissionProfile
    var environmentId: String
    var resume: CheckedContinuation<RequestPermissionsResponse, Never>?

    init(
        requestedPermissions: RequestPermissionProfile,
        environmentId: String,
        resume: CheckedContinuation<RequestPermissionsResponse, Never>? = nil
    ) {
        self.requestedPermissions = requestedPermissions
        self.environmentId = environmentId
        self.resume = resume
    }
}

final class RunningTask: @unchecked Sendable {
    var kind: TaskKind
    var cancellation: Task<Void, Never>?
    var turnContext: TurnContext
    var done: Bool

    init(kind: TaskKind, turnContext: TurnContext) {
        self.kind = kind
        self.turnContext = turnContext
        self.done = false
    }
}

final class ActiveTurn: @unchecked Sendable {
    var task: RunningTask?
    var turnState: TurnState

    init(task: RunningTask? = nil, turnState: TurnState = TurnState()) {
        self.task = task
        self.turnState = turnState
    }
}

final class TurnState: @unchecked Sendable {
    var pendingApprovals: [String: CheckedContinuation<CodexProtocol.ReviewDecision, Never>] = [:]
    var pendingRequestPermissions: [String: PendingRequestPermissions] = [:]
    var pendingUserInput: [String: CheckedContinuation<AcceptedUserInputResponse, Never>] = [:]
    var pendingDynamicTools: [String: CheckedContinuation<DynamicToolResponse, Never>] = [:]
    var pendingInput = SessionTurnInputQueue()
    var mailboxDeliveryPhase: MailboxDeliveryPhase = .currentTurn
    var grantedPermissionsByEnvironmentId: [String: AdditionalPermissionProfile] = [:]
    var strictAutoReviewEnabled = false
    var toolCalls: UInt64 = 0
    var hasMemoryCitation = false
    var tokenUsageAtTurnStart = CodexProtocol.TokenUsage()
    var tokenUsageByModel = TurnTokenUsage()
    var lastKnownStepContext: StepContext?

    init() {}

    func insertPendingApproval(
        key: String,
        continuation: CheckedContinuation<CodexProtocol.ReviewDecision, Never>
    ) -> CheckedContinuation<CodexProtocol.ReviewDecision, Never>? {
        let previous = pendingApprovals[key]
        pendingApprovals[key] = continuation
        return previous
    }

    func removePendingApproval(key: String) -> CheckedContinuation<CodexProtocol.ReviewDecision, Never>? {
        pendingApprovals.removeValue(forKey: key)
    }

    func clearPendingWaiters() {
        pendingApprovals.removeAll()
        pendingRequestPermissions.removeAll()
        pendingUserInput.removeAll()
        pendingDynamicTools.removeAll()
    }

    func insertPendingRequestPermissions(
        key: String,
        pending: PendingRequestPermissions
    ) -> PendingRequestPermissions? {
        let previous = pendingRequestPermissions[key]
        pendingRequestPermissions[key] = pending
        return previous
    }

    func removePendingRequestPermissions(key: String) -> PendingRequestPermissions? {
        pendingRequestPermissions.removeValue(forKey: key)
    }

    func insertPendingUserInput(
        key: String,
        continuation: CheckedContinuation<AcceptedUserInputResponse, Never>
    ) -> CheckedContinuation<AcceptedUserInputResponse, Never>? {
        let previous = pendingUserInput[key]
        pendingUserInput[key] = continuation
        return previous
    }

    func removePendingUserInput(key: String) -> CheckedContinuation<AcceptedUserInputResponse, Never>? {
        pendingUserInput.removeValue(forKey: key)
    }

    func insertPendingDynamicTool(
        key: String,
        continuation: CheckedContinuation<DynamicToolResponse, Never>
    ) -> CheckedContinuation<DynamicToolResponse, Never>? {
        let previous = pendingDynamicTools[key]
        pendingDynamicTools[key] = continuation
        return previous
    }

    func removePendingDynamicTool(key: String) -> CheckedContinuation<DynamicToolResponse, Never>? {
        pendingDynamicTools.removeValue(forKey: key)
    }

    func acceptMailboxDeliveryForCurrentTurn() {
        mailboxDeliveryPhase = .currentTurn
    }

    func acceptsMailboxDeliveryForCurrentTurn() -> Bool {
        mailboxDeliveryPhase == .currentTurn
    }

    func recordGrantedPermissions(
        environmentId: String,
        permissions: AdditionalPermissionProfile
    ) {
        grantedPermissionsByEnvironmentId[environmentId] = mergePermissionProfiles(
            base: grantedPermissionsByEnvironmentId[environmentId],
            permissions: permissions
        ) ?? permissions
    }

    func grantedPermissions(environmentId: String) -> AdditionalPermissionProfile? {
        grantedPermissionsByEnvironmentId[environmentId]
    }

    func enableStrictAutoReview() {
        strictAutoReviewEnabled = true
    }
}
