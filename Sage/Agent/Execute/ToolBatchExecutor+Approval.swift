//
//  ToolBatchExecutor+Approval.swift
//  Sage
//

import Foundation

extension ToolBatchExecutor {
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
