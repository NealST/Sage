//
//  ToolBatchExecutor+Waves.swift
//  Sage
//
//  Approval-first dispatch: pause the whole batch if any step still needs a
//  gate, then admit the rest through ParallelAdmission (read vs write lock).
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

    /// Codex starts every call, then admits them through an RWLock.
    /// Approval still happens first so a HUD card is a single pause.
    ///
    /// `SessionOperationGate` is a busy lock: the turn cannot sit inside
    /// `operations.run` while `confirmToolApproval` tries to `begin()`.
    static func runAdmittedBatch(
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        var approved: [Int] = []
        for index in plan.steps.indices {
            if shouldSkip(plan.steps[index], services: services) { continue }
            if let blocked = await gateSerialStep(plan.steps[index], at: index, plan: &plan, services: services) {
                return blocked
            }
            approved.append(index)
        }
        guard !approved.isEmpty else { return .succeeded }
        guard await markParallelRunning(approved, plan: &plan, services: services) else {
            return .persistFailed
        }
        let steps = plan.steps
        let gate = ParallelAdmission()
        let tasks = approved.map { index in
            Task { @MainActor in
                let exclusive = !ParallelToolRuntime.supportsParallel(steps[index].toolName)
                let outcome: StepCallResult
                if exclusive {
                    outcome = await gate.write { await invoke(steps[index], services: services) }
                } else {
                    outcome = await gate.read { await invoke(steps[index], services: services) }
                }
                return IndexedResult(index: index, result: outcome)
            }
        }
        var collected: [IndexedResult] = []
        for task in tasks {
            collected.append(await task.value)
        }
        return await foldParallelResults(collected, plan: &plan, services: services)
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

    static func foldParallelResults(
        _ results: [IndexedResult],
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        var cancelled = false
        for item in results {
            if case .needsEscalationApproval(let reason) = item.result {
                plan.steps[item.index].status = .pending
                let step = plan.steps[item.index]
                let card = AgentStep(
                    id: step.id,
                    toolCallID: step.toolCallID,
                    toolName: step.toolName,
                    argumentsJSON: step.argumentsJSON,
                    title: SandboxEscalation.title(reason: reason, original: step.title),
                    status: .pending
                )
                return await pauseForApproval(card, plan: plan, services: services)
            }
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
                argumentsJSON: step.argumentsJSON,
                toolCallID: step.toolCallID
            )
            return .success(raw)
        } catch is CancellationError {
            return .cancelled
        } catch let error as HarnessToolError {
            if case .needsEscalationApproval(let reason) = error {
                return .needsEscalationApproval(reason)
            }
            return .failure(error.localizedDescription)
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
