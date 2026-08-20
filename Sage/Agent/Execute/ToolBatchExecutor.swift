//
//  ToolBatchExecutor.swift
//  Sage
//
//  Runs one in-flight tool batch for the execute agent. Not the work plan.
//

import Foundation

/// Confirm-resume / step runner / Stop / Cancel for a tool batch.
enum ToolBatchExecutor {
    private enum WaveOutcome: Equatable {
        case ok
        case paused
        case persistFailed
        case cancelled
    }

    private enum StepCallResult: Sendable {
        case success(String)
        case failure(String)
        case cancelled
    }

    static func execute(
        initialPlan: AgentPlan,
        services: ExecuteServices,
        retryFailedSteps: Bool = false
    ) async {
        // Always normalize before Run/Retry so Dismiss→Run and relaunch can't skip
        // remaining steps or duplicate ERROR tool results.
        guard var plan = await prepareForResume(
            plan: initialPlan,
            services: services,
            retryFailedSteps: retryFailedSteps
        ) else { return }
        services.planProgress.replace(plan)
        services.state.enterExecuting()

        // After the batch is committed, Stop must not re-attach this finished plan.
        var stopPlan: AgentPlan? = plan
        do {
            for wave in ToolBatchWave.partition(plan.steps) {
                try Task.checkCancellation()
                switch await runWave(wave, plan: &plan, services: services) {
                case .ok:
                    try Task.checkCancellation()
                    continue
                case .paused:
                    return
                case .persistFailed:
                    return
                case .cancelled:
                    throw CancellationError()
                }
            }
            try Task.checkCancellation()

            guard await services.commit(
                appendEvents: [],
                deleteEventIDs: [],
                mutate: { task in
                    task.pendingPlan = nil
                }
            ) else {
                await services.failDuringExecution(
                    plan: plan,
                    message: "Could not save progress. Retry to continue remaining steps."
                )
                return
            }
            services.planProgress.clear()
            stopPlan = nil

            if !services.allowToolsAfterExecute() {
                await services.pauseForToolRoundLimit()
                return
            }

            services.state.enterThinking()
            try Task.checkCancellation()
            let turn = try await services.requestModelStreaming(includeTools: true)
            try Task.checkCancellation()
            await services.continueTurn(turn)
        } catch is CancellationError {
            services.clearStream()
            await handleStop(plan: stopPlan, services: services)
        } catch {
            services.clearStream()
            await services.markFailed(error.localizedDescription)
        }
    }

    /// Clears ERROR tool results and reopens failed/skipped/running steps before Retry.
    /// Resume after a pause only resets interrupted `.running` steps.
    static func prepareForResume(
        plan: AgentPlan,
        services: ExecuteServices,
        retryFailedSteps: Bool
    ) async -> AgentPlan? {
        var plan = plan
        let errorEventIDs = retryFailedSteps
            ? errorToolResultIDs(in: services.events, matching: plan)
            : []
        let succeededCallIDs = AgentEventHelpers.successfulToolCallIDs(in: services.events)

        for index in plan.steps.indices {
            if succeededCallIDs.contains(plan.steps[index].toolCallID) {
                plan.steps[index].status = .succeeded
                continue
            }
            if retryFailedSteps {
                if plan.steps[index].status == .failed
                    || plan.steps[index].status == .skipped
                    || plan.steps[index].status == .running {
                    plan.steps[index].status = .pending
                    plan.steps[index].result = nil
                }
            } else if plan.steps[index].status == .running {
                plan.steps[index].status = .pending
                plan.steps[index].result = nil
            }
        }

        let ok = await services.commit(
            appendEvents: [],
            deleteEventIDs: errorEventIDs,
            mutate: { task in
                task.pendingPlan = plan
                task.pendingPrompt = nil
                task.status = .active
            }
        )
        guard ok else { return nil }
        services.planProgress.replace(plan)
        return plan
    }

    @discardableResult
    static func cancelPendingPlan(services: ExecuteServices) async -> Bool {
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: services.events)
        let text = "Cancelled. Nothing was changed."
        let cancelEvent = AgentEvent(kind: .assistantResponse, content: text)

        guard await services.commit(
            appendEvents: [cancelEvent],
            deleteEventIDs: retractIDs,
            mutate: { task in
                task.pendingPlan = nil
                task.pendingPrompt = nil
                task.workPlan = nil
                task.status = .active
            }
        ) else { return false }

        services.state.clearPendingPrompt()
        services.planProgress.clear()
        services.state.lastAssistantText = text
        services.state.enterIdle()
        return true
    }

    static func handleStop(plan: AgentPlan?, services: ExecuteServices) async {
        if var plan {
            for index in plan.steps.indices where plan.steps[index].status == .running {
                plan.steps[index].status = .pending
            }
            await services.failDuringExecution(
                plan: plan,
                message: "Stopped. Retry to continue remaining steps."
            )
            return
        }

        // Keep a Retry path when work was already committed (user turn / tool results).
        switch services.events.last?.kind {
        case .toolResult:
            services.state.enterFailed(message: "Stopped. Retry to summarize.")
        case .userInput:
            services.state.enterFailed(message: "Stopped. Retry to continue.")
        default:
            services.state.enterIdle()
        }
    }

    /// Retry only removes ERROR results for this batch, not earlier rounds.
    nonisolated static func errorToolResultIDs(in events: [AgentEvent], matching plan: AgentPlan) -> [UUID] {
        let callIDs = Set(plan.steps.map(\.toolCallID))
        return events.compactMap { event in
            guard event.kind == .toolResult,
                  event.content.hasPrefix("ERROR:"),
                  let id = event.toolCallID,
                  callIDs.contains(id)
            else { return nil }
            return event.id
        }
    }

    static func makePlan(
        from toolCalls: [ToolCallProposal],
        summary: String,
        pathGuardPolicy: PathGuard.Policy = .home
    ) -> AgentPlan {
        AgentPlan(
            summary: summary,
            steps: toolCalls.map { call in
                AgentStep(
                    toolCallID: call.id,
                    toolName: call.name,
                    argumentsJSON: call.argumentsJSON,
                    title: ToolCallPresentation.humanTitle(
                        name: call.name,
                        argumentsJSON: call.argumentsJSON,
                        policy: pathGuardPolicy
                    )
                )
            }
        )
    }

    // MARK: - Waves

    private static func runWave(
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

    private static func runSerialStep(
        _ index: Int,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        guard plan.steps.indices.contains(index) else { return .ok }
        if shouldSkip(plan.steps[index], services: services) {
            return .ok
        }

        let step = plan.steps[index]
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

        let hookReason: String? = if case .ask(let reason) = hookDecision {
            reason
        } else {
            nil
        }
        let requiresApproval = hookReason != nil
            || SessionToolAllowlist.needsGate(forToolNamed: step.toolName)
        if requiresApproval,
           !services.isToolApproved(step.toolName, step.argumentsJSON) {
            return await pauseForApproval(
                approvalStep(step, hookReason: hookReason),
                plan: plan,
                services: services
            )
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

    private static func runParallelSteps(
        _ indices: [Int],
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        var runnable = indices.filter { index in
            plan.steps.indices.contains(index) && !shouldSkip(plan.steps[index], services: services)
        }
        guard !runnable.isEmpty else { return .ok }

        var approved: [Int] = []
        for index in runnable {
            let step = plan.steps[index]
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
                guard result == .ok else { return result }
                continue
            }

            let hookReason: String? = if case .ask(let reason) = hookDecision {
                reason
            } else {
                nil
            }
            let requiresApproval = hookReason != nil
                || SessionToolAllowlist.needsGate(forToolNamed: step.toolName)
            if requiresApproval,
               !services.isToolApproved(step.toolName, step.argumentsJSON) {
                return await pauseForApproval(
                    approvalStep(step, hookReason: hookReason),
                    plan: plan,
                    services: services
                )
            }
            approved.append(index)
        }
        runnable = approved
        guard !runnable.isEmpty else { return .ok }

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
            return .persistFailed
        }

        struct IndexedResult: Sendable {
            var index: Int
            var result: StepCallResult
        }

        let steps = plan.steps
        let captured = runnable.map { (index: $0, step: steps[$0]) }
        let pending = captured.map { item in
            Task { @MainActor in
                let outcome = await invoke(item.step, services: services)
                return IndexedResult(index: item.index, result: outcome)
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

        var cancelled = false
        for item in results {
            if case .cancelled = item.result {
                plan.steps[item.index].status = .pending
                cancelled = true
                continue
            }
            switch await applyOutcome(item.result, at: item.index, plan: &plan, services: services) {
            case .ok:
                continue
            case .paused:
                return .paused
            case .persistFailed:
                return .persistFailed
            case .cancelled:
                cancelled = true
            }
        }
        return cancelled ? .cancelled : .ok
    }

    private static func shouldSkip(_ step: AgentStep, services: ExecuteServices) -> Bool {
        if step.status == .succeeded { return true }
        if AgentEventHelpers.hasSuccessfulToolResult(for: step.toolCallID, in: services.events) {
            return true
        }
        if step.status == .failed {
            return services.events.contains {
                $0.kind == .toolResult && $0.toolCallID == step.toolCallID
            }
        }
        return false
    }

    private static func invoke(
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

    private static func applyOutcome(
        _ outcome: StepCallResult,
        at index: Int,
        plan: inout AgentPlan,
        services: ExecuteServices
    ) async -> WaveOutcome {
        let step = plan.steps[index]
        let resultEvent: AgentEvent
        switch outcome {
        case .success(let result):
            plan.steps[index].status = .succeeded
            plan.steps[index].result = result
            let isSkillContext = step.toolName == "load_skill"
                || step.toolName == "load_skill_resource"
            resultEvent = AgentEvent(
                kind: .toolResult,
                content: result,
                toolCallID: step.toolCallID,
                protected: isSkillContext
            )
        case .cancelled:
            plan.steps[index].status = .pending
            return .cancelled
        case .failure(let message):
            plan.steps[index].status = .failed
            plan.steps[index].result = message
            resultEvent = AgentEvent(
                kind: .toolResult,
                content: "ERROR: \(message)",
                toolCallID: step.toolCallID
            )
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
        return .ok
    }

    private static func pauseForApproval(
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

    private static func approvalStep(
        _ step: AgentStep,
        hookReason: String?
    ) -> AgentStep {
        guard let hookReason else { return step }
        var copy = step
        copy.title = "\(hookReason)\n\(step.title)"
        return copy
    }
}
