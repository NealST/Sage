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

import CodexAsyncUtils
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
    /// Absent in legacy guardian mode, which does not reserve an order.
    var acceptanceOrder: UInt64?

    init(response: RequestUserInputResponse, acceptanceOrder: UInt64?) {
        self.response = response
        self.acceptanceOrder = acceptanceOrder
    }
}

/// Resumes a command-approval waiter at most once. Clearing the turn, a
/// replacement request, and the user's decision can all observe the same id.
final class ApprovalDecision: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CodexProtocol.ReviewDecision, Never>?

    init(_ continuation: CheckedContinuation<CodexProtocol.ReviewDecision, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: CodexProtocol.ReviewDecision) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

/// Resumes an MCP elicitation waiter at most once. A replacement request
/// cancels the previous waiter immediately. Clearing the turn does too.
final class ElicitationDecision: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ElicitationResponse?, Never>?

    init(_ continuation: CheckedContinuation<ElicitationResponse?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: ElicitationResponse?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

struct PendingElicitationKey: Hashable, Sendable {
    var serverName: String
    var requestId: RequestId
}

/// Resumes a dynamic-tool waiter at most once. A replacement request holds
/// the previous waiter until the new call finishes, and clearing the turn
/// can resume it as well.
final class DynamicToolDecision: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DynamicToolResponse?, Never>?

    init(_ continuation: CheckedContinuation<DynamicToolResponse?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: DynamicToolResponse?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

/// Resumes a `request_permissions` waiter at most once. Cancellation, a
/// replacement request, and the user's answer can all observe the same call.
final class PermissionsDecision: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RequestPermissionsResponse?, Never>?

    init(_ continuation: CheckedContinuation<RequestPermissionsResponse?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: RequestPermissionsResponse?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

struct PendingRequestPermissions: Sendable {
    /// Distinguishes a replacement request that reused this call id.
    var requestId: UUID
    var requestedPermissions: RequestPermissionProfile
    var environmentId: String
    var policyContext: FileSystemSandboxPolicyContext?
    var decision: PermissionsDecision

    init(
        requestId: UUID,
        requestedPermissions: RequestPermissionProfile,
        environmentId: String,
        policyContext: FileSystemSandboxPolicyContext? = nil,
        decision: PermissionsDecision
    ) {
        self.requestId = requestId
        self.requestedPermissions = requestedPermissions
        self.environmentId = environmentId
        self.policyContext = policyContext
        self.decision = decision
    }
}

final class RunningTask: @unchecked Sendable {
    var kind: TaskKind
    var cancellation: Task<Void, Never>?
    var cancellationToken: CancellationToken?
    var turnContext: TurnContext
    var done: Bool

    init(
        kind: TaskKind,
        turnContext: TurnContext,
        cancellationToken: CancellationToken? = nil
    ) {
        self.kind = kind
        self.turnContext = turnContext
        self.cancellationToken = cancellationToken
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
    var pendingApprovals: [String: ApprovalDecision] = [:]
    var pendingRequestPermissions: [String: PendingRequestPermissions] = [:]
    var pendingUserInput: [String: CheckedContinuation<AcceptedUserInputResponse?, Never>] = [:]
    var pendingDynamicTools: [String: DynamicToolDecision] = [:]
    var pendingElicitations: [PendingElicitationKey: ElicitationDecision] = [:]
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
        decision: ApprovalDecision
    ) -> ApprovalDecision? {
        let previous = pendingApprovals[key]
        pendingApprovals[key] = decision
        return previous
    }

    func removePendingApproval(key: String) -> ApprovalDecision? {
        pendingApprovals.removeValue(forKey: key)
    }

    func clearPendingWaiters() {
        let approvals = pendingApprovals
        pendingApprovals.removeAll()
        for decision in approvals.values {
            decision.resume(.abort)
        }
        let permissions = pendingRequestPermissions
        pendingRequestPermissions.removeAll()
        for pending in permissions.values {
            pending.decision.resume(nil)
        }
        let userInput = pendingUserInput
        pendingUserInput.removeAll()
        for continuation in userInput.values {
            continuation.resume(returning: nil)
        }
        let dynamicTools = pendingDynamicTools
        pendingDynamicTools.removeAll()
        for decision in dynamicTools.values {
            decision.resume(nil)
        }
        let elicitations = pendingElicitations
        pendingElicitations.removeAll()
        for decision in elicitations.values {
            decision.resume(nil)
        }
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
        continuation: CheckedContinuation<AcceptedUserInputResponse?, Never>
    ) -> CheckedContinuation<AcceptedUserInputResponse?, Never>? {
        let previous = pendingUserInput[key]
        pendingUserInput[key] = continuation
        return previous
    }

    func removePendingUserInput(key: String) -> CheckedContinuation<AcceptedUserInputResponse?, Never>? {
        pendingUserInput.removeValue(forKey: key)
    }

    func insertPendingDynamicTool(
        key: String,
        decision: DynamicToolDecision
    ) -> DynamicToolDecision? {
        let previous = pendingDynamicTools[key]
        pendingDynamicTools[key] = decision
        return previous
    }

    func removePendingDynamicTool(key: String) -> DynamicToolDecision? {
        pendingDynamicTools.removeValue(forKey: key)
    }

    func insertPendingElicitation(
        serverName: String,
        requestId: RequestId,
        decision: ElicitationDecision
    ) -> ElicitationDecision? {
        let key = PendingElicitationKey(serverName: serverName, requestId: requestId)
        let previous = pendingElicitations[key]
        pendingElicitations[key] = decision
        return previous
    }

    func removePendingElicitation(
        serverName: String,
        requestId: RequestId
    ) -> ElicitationDecision? {
        pendingElicitations.removeValue(
            forKey: PendingElicitationKey(serverName: serverName, requestId: requestId))
    }

    func acceptMailboxDeliveryForCurrentTurn() {
        mailboxDeliveryPhase = .currentTurn
    }

    func setMailboxDeliveryPhase(_ phase: MailboxDeliveryPhase) {
        mailboxDeliveryPhase = phase
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
