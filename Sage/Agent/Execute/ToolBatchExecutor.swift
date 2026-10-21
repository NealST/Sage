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

    /// Approval gate for a harness turn, before `runTurn` dispatches tools.
    /// `.ready` means every remaining step may run inside the harness.
    /// `.halted` means a step was recorded terminal and the model should sample again.
    enum AdmitOutcome: Equatable, Sendable {
        case ready
        case paused
        case halted
        case persistFailed
        case cancelled
    }

    enum StepCallResult: Sendable {
        case success(String)
        case failure(String)
        case cancelled
        case needsEscalationApproval(String)
    }

    @discardableResult
    static func discardUnconfirmedPlan(services: ExecuteServices) async -> Bool {
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: services.events)
        guard await services.commit(
            appendEvents: [],
            deleteEventIDs: retractIDs,
            mutate: clearUnconfirmedPlan
        ) else { return false }
        services.state.clearPendingPrompt()
        services.planProgress.clear()
        return true
    }

    @discardableResult
    static func cancelPendingPlan(services: ExecuteServices) async -> Bool {
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: services.events)
        let text = "Cancelled. Nothing was changed."
        let cancelEvent = AgentEvent(kind: .assistantResponse, content: text)

        guard await services.commit(
            appendEvents: [cancelEvent],
            deleteEventIDs: retractIDs,
            mutate: clearUnconfirmedPlan
        ) else { return false }

        services.state.clearPendingPrompt()
        services.planProgress.clear()
        services.state.lastAssistantText = text
        services.state.enterIdle()
        return true
    }

    private static func clearUnconfirmedPlan(_ task: inout TaskRecord) {
        task.pendingPlan = nil
        task.pendingPrompt = nil
        task.clearWorkPlan()
        task.status = .active
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
