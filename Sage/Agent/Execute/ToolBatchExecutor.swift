//
//  ToolBatchExecutor.swift
//  Sage
//
//  Runs one in-flight tool batch for the execute agent. Not the work plan.
//

import Foundation

/// Confirm-resume / step runner / Stop / Cancel for a tool batch.
enum ToolBatchExecutor {
    enum WaveOutcome: Equatable {
        case succeeded
        case paused
        case persistFailed
        case cancelled
    }

    enum StepCallResult: Sendable {
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
                case .succeeded:
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
            let finished = try await finishSuccessfulBatch(plan: plan, services: services)
            if finished {
                stopPlan = nil
            }
        } catch is CancellationError {
            services.clearStream()
            await handleStop(plan: stopPlan, services: services)
        } catch {
            services.clearStream()
            await services.markFailed(error.localizedDescription)
        }
    }

    static func finishSuccessfulBatch(plan: AgentPlan, services: ExecuteServices) async throws -> Bool {
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
            return false
        }
        services.planProgress.clear()
        if !services.allowToolsAfterExecute() {
            await services.pauseForToolRoundLimit()
            return true
        }
        services.state.enterThinking()
        try Task.checkCancellation()
        let turn = try await services.requestModelStreaming(includeTools: true)
        try Task.checkCancellation()
        await services.continueTurn(turn)
        return true
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

        let didCommit = await services.commit(
            appendEvents: [],
            deleteEventIDs: errorEventIDs
        ) { task in
                task.pendingPlan = plan
                task.pendingPrompt = nil
                task.status = .active
        }
        guard didCommit else { return nil }
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
        if services.state.turnInput.pendingSteer != nil {
            // Redirect: persistSteerTurn retracts the batch after cancel. Do not fail the task.
            services.clearStream()
            return
        }
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
}
