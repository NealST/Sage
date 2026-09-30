//
//  ToolBatchExecutor+Approval.swift
//  Sage
//

import CodexProtocol
import Foundation

extension ToolBatchExecutor {
    enum GuardianGate: Equatable, Sendable {
        case continueBatch
        case askHUD
        case deny(String)
        case abort
    }

    /// Isolated reviewer before the HUD card. `nil` / ASK still pause the
    /// whole batch — never wait inside `runTurn` / `operations.run`.
    static func reviewMissingApproval(
        _ step: AgentStep,
        hookApproval: PreToolUseApproval?,
        services: ExecuteServices
    ) async -> GuardianGate {
        let retry = SandboxEscalation.isEscalation(step.title)
        let action = ApprovalAction.from(
            step: step,
            cwd: services.state.pathGuardPolicy.defaultWorkingDirectory
        )
        let pathPolicy = services.state.pathGuardPolicy
        let reviewer = GuardianReviewRequest.approvalsReviewer(for: pathPolicy)
        guard GuardianReviewRequest.routesToGuardian(
            policy: pathPolicy,
            retry: retry,
            scope: GuardianApprovalRequest.from(action).scope,
            approvalPolicy: CodexProtocol.AskForApproval.onRequest,
            reviewer: reviewer
        ) else {
            return .askHUD
        }
        let reviewed = await GuardianDecision.decide(
            action: action,
            context: ApprovalContext(
                callID: step.toolCallID,
                toolName: step.toolName,
                approvalReason: hookApproval?.reason,
                retryReason: retry ? step.title : nil
            ),
            options: GuardianReviewOptions(
                requireGuardian: Guardian.requiresReview(
                    policy: pathPolicy,
                    retry: retry
                ),
                approvalPolicy: CodexProtocol.AskForApproval.onRequest,
                approvalsReviewer: reviewer
            ),
            events: services.events
        )
        guard let reviewed else { return .askHUD }
        switch reviewed {
        case .approved, .approvedForSession:
            acceptGuardianApproval(
                reviewed,
                step: step,
                hookApproval: hookApproval,
                services: services
            )
            return .continueBatch

        case .denied(let reason):
            return .deny("Guardian denied this action: \(reason)")

        case .abort:
            return .abort
        }
    }

    static func acceptGuardianApproval(
        _ decision: ReviewDecision,
        step: AgentStep,
        hookApproval: PreToolUseApproval?,
        services: ExecuteServices
    ) {
        let policy = services.state.pathGuardPolicy
        let skills = services.skillHost.catalogSkills
        let mcpTools = services.mcp?.mcpTools ?? []
        switch decision {
        case .approved:
            services.state.sessionAllowlist.allowCapabilityOnce(
                name: step.toolName,
                argumentsJSON: step.argumentsJSON,
                policy: policy,
                skills: skills,
                mcpTools: mcpTools
            )

        case .approvedForSession:
            services.state.sessionAllowlist.allowThisTask(
                name: step.toolName,
                argumentsJSON: step.argumentsJSON,
                policy: policy,
                scopeID: services.state.authorizationScopeID,
                skills: skills,
                mcpTools: mcpTools
            )

        case .denied, .abort:
            return
        }
        if let hookApproval {
            services.state.sessionAllowlist.allowHookOnce(
                name: step.toolName,
                argumentsJSON: step.argumentsJSON,
                hookIdentity: hookApproval.identity
            )
        }
    }

    static func isApprovalMissing(
        for step: AgentStep,
        hookApproval: PreToolUseApproval?,
        services: ExecuteServices
    ) -> Bool {
        let needsCapability = services.requiresAuthorization(
            name: step.toolName,
            argumentsJSON: step.argumentsJSON
        )
        let capabilityMissing = needsCapability
            && !services.isToolApproved(step.toolName, step.argumentsJSON)
        let hookMissing = hookApproval.map { approval in
            !services.isHookApproved(
                step.toolName,
                step.argumentsJSON,
                approval.identity
            )
        } ?? false
        return capabilityMissing || hookMissing
    }

    static func validationError(
        for step: AgentStep,
        services: ExecuteServices
    ) -> String? {
        do {
            try services.validateToolInvocation(
                name: step.toolName,
                argumentsJSON: step.argumentsJSON
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func pauseForApproval(
        _ step: AgentStep,
        plan: AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        let prompt = AgentPendingPrompt.toolApproval(
            toolCallID: step.toolCallID,
            toolName: step.toolName,
            argumentsJSON: step.argumentsJSON,
            title: step.title
        )
        guard await services.commit(
            appendEvents: [],
            deleteEventIDs: [],
            mutate: { task in
                task.pendingPlan = plan
                task.pendingPrompt = prompt
                task.status = .awaitingApproval
            }
        ) else {
            await services.failDuringExecution(
                plan: plan,
                message: "Could not save progress. Retry to continue remaining steps."
            )
            return .persistFailed
        }
        services.planProgress.replace(plan)
        await services.pauseForToolApproval(step)
        return .paused
    }

    static func approvalStep(
        _ step: AgentStep,
        hookReason: String?
    ) -> AgentStep {
        guard let hookReason else { return step }
        var copy = step
        copy.title = "\(hookReason)\n\(step.title)"
        return copy
    }
}
