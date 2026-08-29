//
//  ToolBatchExecutor+Waves.swift
//  Sage
//

import Foundation

extension ToolBatchExecutor {
    // MARK: - Waves

    static func runWave(
        _ wave: ToolBatchWave,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        switch wave {
        case .serial(let index):
            return await runSerialStep(index, plan: &plan, services: services)

        case .parallel(let indices):
            return await runParallelSteps(indices, plan: &plan, services: services)
        }
    }

    static func runSerialStep(
        _ index: Int,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        guard plan.steps.indices.contains(index) else { return .succeeded }
        if shouldSkip(plan.steps[index], services: services) {
            return .succeeded
        }

        let step = plan.steps[index]
        if let blocked = await gateSerialStep(step, at: index, plan: &plan, services: services) {
            return blocked
        }

        plan.steps[index].status = .running
        services.planProgress.update(plan)
        guard await services.persistPlanStepStatus(plan.steps[index], in: plan) else {
            await services.failDuringExecution(
                plan: plan,
                message: "Could not save progress. Retry to continue remaining steps."
            )
            return .persistFailed
        }

        let outcome = await invoke(step, services: services)
        return await applyOutcome(outcome, at: index, plan: &plan, services: services)
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
            return await pauseForApproval(
                approvalStep(step, hookReason: hookApproval?.reason),
                plan: plan,
                services: services
            )
        }
        return nil
    }

    static func runParallelSteps(
        _ indices: [Int],
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        let prepared = await prepareParallelRun(indices, plan: &plan, services: services)
        switch prepared {
        case .outcome(let outcome):
            return outcome

        case .runnable(let runnable):
            return await collectParallelResults(runnable, plan: &plan, services: services)
        }
    }

    enum ParallelPrep {
        case outcome(WaveOutcome)
        case runnable([Int])
    }

    static func prepareParallelRun(
        _ indices: [Int],
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> ParallelPrep {
        var runnable = indices.filter { index in
            plan.steps.indices.contains(index) && !shouldSkip(plan.steps[index], services: services)
        }
        guard !runnable.isEmpty else { return .outcome(.succeeded) }

        var approved: [Int] = []
        for index in runnable {
            switch await approveParallelStep(index, plan: &plan, services: services) {
            case .approved:
                approved.append(index)

            case .skipped:
                continue

            case .halt(let outcome):
                return .outcome(outcome)
            }
        }
        runnable = approved
        guard !runnable.isEmpty else { return .outcome(.succeeded) }
        guard await markParallelRunning(runnable, plan: &plan, services: services) else {
            return .outcome(.persistFailed)
        }
        return .runnable(runnable)
    }

    enum ParallelStepPrep {
        case approved
        case skipped
        case halt(WaveOutcome)
    }

    static func approveParallelStep(
        _ index: Int,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> ParallelStepPrep {
        let step = plan.steps[index]
        if let validationError = validationError(for: step, services: services) {
            let result = await applyOutcome(
                .failure(validationError),
                at: index,
                plan: &plan,
                services: services
            )
            return result == .succeeded ? .skipped : .halt(result)
        }
        let hookDecision = await services.evaluatePreToolUse(
            name: step.toolName,
            argumentsJSON: step.argumentsJSON
        )
        if case .deny(let reason) = hookDecision {
            let result = await applyOutcome(
                .failure("Blocked by PreToolUse hook: \(reason)"),
                at: index,
                plan: &plan,
                services: services
            )
            return result == .succeeded ? .skipped : .halt(result)
        }
        let hookApproval: PreToolUseApproval? = if case .ask(let approval) = hookDecision {
            approval
        } else {
            nil
        }
        if isApprovalMissing(
            for: step,
            hookApproval: hookApproval,
            services: services
        ) {
            return .halt(
                await pauseForApproval(
                    approvalStep(step, hookReason: hookApproval?.reason),
                    plan: plan,
                    services: services
                )
            )
        }
        return .approved
    }

    static func markParallelRunning(
        _ runnable: [Int],
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> Bool {
        for index in runnable {
            plan.steps[index].status = .running
        }
        services.planProgress.update(plan)
        guard await services.commit(
            appendEvents: [],
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
            return false
        }
        return true
    }

    struct IndexedResult: Sendable {
        var index: Int
        var result: StepCallResult
    }

    static func collectParallelResults(
        _ runnable: [Int],
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        let steps = plan.steps
        let pending = runnable.map { index in
            Task { @MainActor in
                let outcome = await invoke(steps[index], services: services)
                return IndexedResult(index: index, result: outcome)
            }
        }
        let results: [IndexedResult] = await withTaskCancellationHandler {
            var collected: [IndexedResult] = []
            for task in pending {
                collected.append(await task.value)
            }
            return collected
        } onCancel: {
            for task in pending { task.cancel() }
        }
        return await foldParallelResults(results, plan: &plan, services: services)
    }

    static func foldParallelResults(
        _ results: [IndexedResult],
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        var cancelled = false
        for item in results {
            if case .cancelled = item.result {
                plan.steps[item.index].status = .pending
                cancelled = true
                continue
            }
            switch await applyOutcome(item.result, at: item.index, plan: &plan, services: services) {
            case .succeeded:
                continue

            case .paused:
                return .paused

            case .persistFailed:
                return .persistFailed

            case .cancelled:
                cancelled = true
            }
        }
        return cancelled ? .cancelled : .succeeded
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

    static func invoke(
        _ step: AgentStep,
        services: ExecuteServices
    ) async -> StepCallResult {
        do {
            try Task.checkCancellation()
            let raw = try await services.executeToolInvocation(
                name: step.toolName,
                argumentsJSON: step.argumentsJSON
            )
            return .success(raw)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
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

        case .cancelled:
            plan.steps[index].status = .pending
            return nil

        case .failure(let message):
            plan.steps[index].status = .failed
            plan.steps[index].result = message
            return AgentEvent(
                kind: .toolResult,
                content: "ERROR: \(message)",
                toolCallID: step.toolCallID
            )
        }
    }
}
