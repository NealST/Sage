//
//  exec_approval.swift
//  Sage
//
//  Port of `request_command_approval` / `notify_approval` in
//  codex-rs/core/src/session/mod.rs and `exec_approval` in
//  codex-rs/core/src/session/handlers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A command approval waits on the active turn. The key is `approvalId`
//  when the request sets one, otherwise the tool call id.
//  `Op::ExecApproval` resumes that waiter and does not start a turn.
//  Abort interrupts the active turn instead of delivering a decision.
//  A dropped waiter returns abort. An execpolicy amendment is appended to
//  `codexHome/rules/default.rules` and the in-memory policy. A failure
//  emits a warning and the decision is still delivered. Plugin
//  attribution waits.
//

import CodexCore
import CodexExecPolicy
import CodexProtocol
import CodexShellCommand
import CodexUtils
import Foundation

struct CommandApprovalRequest: Sendable {
    var kind: ExecApprovalKind = .command
    var callId: String
    var approvalId: String?
    var environmentId: String?
    var command: [String]
    var cwd: String
    var reason: String?
    var networkApprovalContext: NetworkApprovalContext?
    var proposedExecpolicyAmendment: ExecPolicyAmendment?
    var additionalPermissions: AdditionalPermissionProfile?
    var availableDecisions: [CodexProtocol.ReviewDecision]?

    init(
        kind: ExecApprovalKind = .command,
        callId: String,
        approvalId: String? = nil,
        environmentId: String? = nil,
        command: [String],
        cwd: String,
        reason: String? = nil,
        networkApprovalContext: NetworkApprovalContext? = nil,
        proposedExecpolicyAmendment: ExecPolicyAmendment? = nil,
        additionalPermissions: AdditionalPermissionProfile? = nil,
        availableDecisions: [CodexProtocol.ReviewDecision]? = nil
    ) {
        self.kind = kind
        self.callId = callId
        self.approvalId = approvalId
        self.environmentId = environmentId
        self.command = command
        self.cwd = cwd
        self.reason = reason
        self.networkApprovalContext = networkApprovalContext
        self.proposedExecpolicyAmendment = proposedExecpolicyAmendment
        self.additionalPermissions = additionalPermissions
        self.availableDecisions = availableDecisions
    }

    var effectiveApprovalId: String { approvalId ?? callId }
}

extension Session {
    /// rust `Session::request_command_approval`.
    func requestCommandApproval(
        turnContext: TurnContext,
        request: CommandApprovalRequest
    ) async -> CodexProtocol.ReviewDecision {
        let replaced = ReplacedApproval()
        let decision: CodexProtocol.ReviewDecision = await withCheckedContinuation { continuation in
            let waiter = ApprovalDecision(continuation)
            if let turn = activeTurn {
                replaced.decision = turn.turnState.insertPendingApproval(
                    key: request.effectiveApprovalId, decision: waiter)
                sendEvent(turnContext, .execApprovalRequest(execApprovalEvent(turnContext, request)))
            } else {
                sendEvent(turnContext, .execApprovalRequest(execApprovalEvent(turnContext, request)))
                waiter.resume(.abort)
            }
        }
        replaced.decision?.resume(.abort)
        return decision
    }

    /// rust `exec_approval`.
    func handleExecApproval(
        id: String,
        turnId: String?,
        decision: CodexProtocol.ReviewDecision
    ) async {
        if case .approvedExecpolicyAmendment(let amendment) = decision,
           let message = await persistExecpolicyAmendment(amendment) {
            sendEventRaw(
                Event(
                    id: turnId ?? id,
                    msg: .warning(WarningEvent(message: message))
                )
            )
        }
        if case .abort = decision {
            await interruptTask()
        } else {
            notifyApproval(id: id, decision: decision)
        }
    }

    /// rust `Session::notify_approval`.
    func notifyApproval(id: String, decision: CodexProtocol.ReviewDecision) {
        guard let turn = activeTurn,
              let waiter = turn.turnState.removePendingApproval(key: id)
        else { return }
        waiter.resume(decision)
    }

    /// rust `Session::persist_execpolicy_amendment`. Returns the warning
    /// text when the amendment cannot be applied.
    private func persistExecpolicyAmendment(_ amendment: ExecPolicyAmendment) async -> String? {
        guard let policy = services.execPolicy else {
            return "Failed to apply execpolicy amendment: exec policy is not configured"
        }
        let manager = ExecPolicyManager(policy)
        do {
            try await manager.appendAmendmentAndUpdate(
                codexHome: state.sessionConfiguration.codexHome,
                amendment: amendment
            )
        } catch {
            return "Failed to apply execpolicy amendment: \((error as CustomStringConvertible).description)"
        }
        services.execPolicy = manager.current()
        return nil
    }
}

final class ReplacedApproval: @unchecked Sendable {
    var decision: ApprovalDecision?
}

private func execApprovalEvent(
    _ turnContext: TurnContext,
    _ request: CommandApprovalRequest
) -> ExecApprovalRequestEvent {
    let proposedNetworkPolicyAmendments = request.networkApprovalContext.map { context in
        [
            NetworkPolicyAmendment(host: context.host, action: .allow),
            NetworkPolicyAmendment(host: context.host, action: .deny),
        ]
    }
    let availableDecisions = request.availableDecisions ?? ExecApprovalRequestEvent.defaultAvailableDecisions(
        networkApprovalContext: request.networkApprovalContext,
        proposedExecpolicyAmendment: request.proposedExecpolicyAmendment,
        proposedNetworkPolicyAmendments: proposedNetworkPolicyAmendments,
        additionalPermissions: request.additionalPermissions
    )
    return ExecApprovalRequestEvent(
        kind: request.kind,
        callId: request.callId,
        approvalId: request.approvalId,
        turnId: turnContext.subId,
        environmentId: request.environmentId,
        startedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
        command: request.command,
        cwd: LegacyAppPathString.fromString(request.cwd),
        reason: request.reason,
        networkApprovalContext: request.networkApprovalContext,
        proposedExecpolicyAmendment: request.proposedExecpolicyAmendment,
        proposedNetworkPolicyAmendments: proposedNetworkPolicyAmendments,
        additionalPermissions: request.additionalPermissions,
        availableDecisions: availableDecisions,
        parsedCmd: parseCommand(request.command)
    )
}
