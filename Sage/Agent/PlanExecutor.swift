//
//  PlanExecutor.swift
//  Sage
//

import Foundation

/// Plan confirm / resume / cancel / stop.
enum PlanExecutor {
    static func execute(initialPlan: AgentPlan, services: PlanServices) async {
        // Always normalize before Run/Retry so Dismiss→Run and relaunch can't skip
        // remaining steps or duplicate ERROR tool results.
        guard var plan = await prepareForResume(plan: initialPlan, services: services) else { return }
        services.planProgress.replace(plan)
        services.state.enterExecuting()

        do {
            for index in plan.steps.indices {
                try Task.checkCancellation()

                if AgentEventHelpers.hasSuccessfulToolResult(
                    for: plan.steps[index].toolCallID,
                    in: services.events
                ) {
                    plan.steps[index].status = .succeeded
                    services.planProgress.update(plan)
                    continue
                }
                if plan.steps[index].status == .succeeded {
                    continue
                }

                plan.steps[index].status = .running
                services.planProgress.update(plan)

                // Refresh the Available Skills appendix for this step (cloud load_skill).
                await services.prepareSkillsForTurn(query: plan.steps[index].title)

                // Step status only — avoid rewriting the whole plan graph on every tick.
                guard await services.persistPlanStepStatus(plan.steps[index], in: plan) else {
                    await services.failDuringExecution(
                        plan: plan,
                        message: "Could not save progress. Retry to continue remaining steps."
                    )
                    return
                }

                let step = plan.steps[index]
                let resultEvent: AgentEvent
                do {
                    try Task.checkCancellation()
                    let rawResult = try await services.executeToolInvocation(
                        name: step.toolName,
                        argumentsJSON: step.argumentsJSON
                    )
                    let result = capToolResult(rawResult)
                    // Side effects may already have landed — persist before honoring Stop.
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
                } catch is CancellationError {
                    plan.steps[index].status = .pending
                    throw CancellationError()
                } catch {
                    plan.steps[index].status = .failed
                    plan.steps[index].result = error.localizedDescription
                    resultEvent = AgentEvent(
                        kind: .toolResult,
                        content: "ERROR: \(error.localizedDescription)",
                        toolCallID: step.toolCallID
                    )

                    for later in (index + 1)..<plan.steps.count
                        where plan.steps[later].status != .succeeded {
                        plan.steps[later].status = .skipped
                    }

                    services.planProgress.update(plan)
                    guard await services.commit(
                        appendEvents: [resultEvent],
                        deleteEventIDs: [],
                        mutate: { task in
                            task.pendingPlan = plan
                            task.status = .awaitingApproval
                        }
                    ) else {
                        await services.failDuringExecution(
                            plan: plan,
                            message: "Could not save progress. Retry to continue remaining steps."
                        )
                        return
                    }
                    await services.failDuringExecution(
                        plan: plan,
                        message: "Step failed: \(error.localizedDescription)"
                    )
                    return
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
                    return
                }

                if step.toolName == "load_skill",
                   let name = services.loadSkillName(from: step.argumentsJSON),
                   !resultEvent.content.hasPrefix("ERROR:") {
                    services.activateSkill(named: name)
                }

                // Stop between steps only — never discard a committed success.
                try Task.checkCancellation()
            }

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
            services.state.phase = .thinking
            services.clearStream()

            try Task.checkCancellation()
            let turn = try await services.requestModelStreaming(includeTools: false)
            try Task.checkCancellation()
            let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String
            if let summary, !summary.isEmpty {
                text = summary
            } else {
                let fallback = plan.steps.compactMap(\.result).joined(separator: "\n")
                text = fallback.isEmpty ? "Done." : fallback
            }
            guard await services.commit(
                appendEvents: [AgentEvent(kind: .assistantResponse, content: text)],
                deleteEventIDs: [],
                mutate: { task in
                    task.status = .completed
                }
            ) else {
                services.clearStream()
                services.state.phase = .failed(message: "Could not save the completion summary.")
                return
            }
            services.clearStream()
            services.state.lastAssistantText = text
            services.state.phase = .completed(summary: text)
            services.generateTopicIfNeeded()
        } catch is CancellationError {
            services.clearStream()
            await handleStop(plan: plan, services: services)
        } catch {
            services.clearStream()
            await services.markFailed(error.localizedDescription)
        }
    }

    /// Clears ERROR tool results and reopens failed/skipped/running steps before Run/Retry.
    static func prepareForResume(plan: AgentPlan, services: PlanServices) async -> AgentPlan? {
        var plan = plan
        let errorEventIDs = services.events.compactMap { event -> UUID? in
            guard event.kind == .toolResult,
                  event.content.hasPrefix("ERROR:")
            else { return nil }
            return event.id
        }

        for index in plan.steps.indices {
            if AgentEventHelpers.hasSuccessfulToolResult(
                for: plan.steps[index].toolCallID,
                in: services.events
            ) {
                plan.steps[index].status = .succeeded
                continue
            }
            if plan.steps[index].status == .failed
                || plan.steps[index].status == .skipped
                || plan.steps[index].status == .running {
                plan.steps[index].status = .pending
                plan.steps[index].result = nil
            }
        }

        let ok = await services.commit(
            appendEvents: [],
            deleteEventIDs: errorEventIDs,
            mutate: { task in
                task.pendingPlan = plan
                task.status = .awaitingApproval
            }
        )
        guard ok else { return nil }
        services.planProgress.replace(plan)
        return plan
    }

    @discardableResult
    static func cancelPendingPlan(services: PlanServices) async -> Bool {
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: services.events)
        let text = "Cancelled. Nothing was changed."
        let cancelEvent = AgentEvent(kind: .assistantResponse, content: text)

        guard await services.commit(
            appendEvents: [cancelEvent],
            deleteEventIDs: retractIDs,
            mutate: { task in
                task.pendingPlan = nil
                task.status = .active
            }
        ) else { return false }

        services.planProgress.clear()
        services.state.lastAssistantText = text
        services.state.phase = .idle
        return true
    }

    static func handleStop(plan: AgentPlan?, services: PlanServices) async {
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
            services.state.phase = .failed(message: "Stopped. Retry to summarize.")
        case .userInput:
            services.state.phase = .failed(message: "Stopped. Retry to continue.")
        default:
            services.state.phase = .idle
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
