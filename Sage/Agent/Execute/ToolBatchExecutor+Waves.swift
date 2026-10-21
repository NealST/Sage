//
//  ToolBatchExecutor+Waves.swift
//  Sage
//
//  Approval-first admission: pause the whole batch if any step still needs a
//  gate. Tool execution itself happens in `runTurn` through
//  `RegularTask.dispatchSageTool`, not here.
//

import Foundation

extension ToolBatchExecutor {
    /// Runs the approval / validation gate and does not invoke tools.
    /// A HUD pause still leaves the turn so the card is not inside `runTurn`.
    static func admit(
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> AdmitOutcome {
        for index in plan.steps.indices {
            if shouldSkip(plan.steps[index], services: services) { continue }
            guard let blocked = await gateSerialStep(
                plan.steps[index],
                at: index,
                plan: &plan,
                services: services
            ) else { continue }
            switch blocked {
            case .succeeded:
                return .halted
            case .paused:
                return .paused
            case .persistFailed:
                return .persistFailed
            case .cancelled:
                return .cancelled
            }
        }
        return .ready
    }

    private static func gateSerialStep(
        _ step: AgentStep,
        at index: Int,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome? {
        if let validationError = validationError(for: step, services: services) {
            return await applyOutcome(
                .failure(validationError),
                at: index,
                plan: &plan,
                services: services
            )
        }
        let hookDecision = await services.evaluatePreToolUse(
            name: step.toolName,
            argumentsJSON: step.argumentsJSON
        )
        if case .deny(let reason) = hookDecision {
            return await applyOutcome(
                .failure("Blocked by PreToolUse hook: \(reason)"),
                at: index,
                plan: &plan,
                services: services
            )
        }
        let hookApproval: PreToolUseApproval? = if case .ask(let approval) = hookDecision {
            approval
        } else {
            nil
        }
        if isApprovalMissing(for: step, hookApproval: hookApproval, services: services) {
            switch await reviewMissingApproval(
                step,
                hookApproval: hookApproval,
                services: services
            ) {
            case .continueBatch:
                return nil

            case .deny(let reason):
                return await applyOutcome(
                    .failure(reason),
                    at: index,
                    plan: &plan,
                    services: services
                )

            case .abort:
                return .cancelled

            case .askHUD:
                return await pauseForApproval(
                    approvalStep(step, hookReason: hookApproval?.reason),
                    plan: plan,
                    services: services
                )
            }
        }
        return nil
    }

    static func shouldSkip(_ step: AgentStep, services: ExecuteServices) -> Bool {
        if step.status == .succeeded { return true }
        if AgentEventHelpers.hasSuccessfulToolResult(for: step.toolCallID, in: services.events) {
            return true
        }
        if step.status == .failed {
            return services.events.contains { event in
                event.kind == .toolResult && event.toolCallID == step.toolCallID
            }
        }
        return false
    }

    static func applyOutcome(
        _ outcome: StepCallResult,
        at index: Int,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        let step = plan.steps[index]
        guard let resultEvent = resultEvent(
            for: outcome,
            step: step,
            at: index,
            plan: &plan,
            services: services
        ) else {
            return .cancelled
        }

        services.planProgress.update(plan)
        guard await services.commit(
            appendEvents: [resultEvent],
            deleteEventIDs: [],
            mutate: { task in
                task.pendingPlan = plan
                task.status = .active
            }
        ) else {
            await services.failDuringExecution(
                plan: plan,
                message: "Could not save progress. Retry to continue remaining steps."
            )
            return .persistFailed
        }

        if case .success = outcome,
           step.toolName == "load_skill",
           let name = services.loadSkillName(from: step.argumentsJSON),
           !resultEvent.content.hasPrefix("ERROR:") {
            services.activateSkill(named: name)
        }
        return .succeeded
    }

    private static func resultEvent(
        for outcome: StepCallResult,
        step: AgentStep,
        at index: Int,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) -> AgentEvent? {
        switch outcome {
        case .success(let result):
            plan.steps[index].status = .succeeded
            plan.steps[index].result = result
            services.state.workspaceChanges.record(
                toolName: step.toolName,
                argumentsJSON: step.argumentsJSON,
                result: result
            )
            let isSkillContext = step.toolName == "load_skill"
                || step.toolName == "load_skill_resource"
            return AgentEvent(
                kind: .toolResult,
                content: result,
                toolCallID: step.toolCallID,
                protected: isSkillContext
            )

        case .cancelled, .needsEscalationApproval:
            plan.steps[index].status = .pending
            return nil

        case .failure(let message):
            plan.steps[index].status = .failed
            plan.steps[index].result = message
            services.state.workspaceChanges.record(
                toolName: step.toolName,
                argumentsJSON: step.argumentsJSON,
                result: message,
                succeeded: false
            )
            return AgentEvent(
                kind: .toolResult,
                content: "ERROR: \(message)",
                toolCallID: step.toolCallID
            )
        }
    }
}
