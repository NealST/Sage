//
//  ExecuteServices.swift
//  Sage
//
//  Dependency bag for ToolBatchExecutor.
//

import Foundation

@MainActor
struct ExecuteServices {
    let state: AgentSessionState
    let planProgress: PlanProgress
    let taskStore: AgentTaskStore
    let modelGateway: AgentModelGateway
    let modelSettings: () -> ModelSettingsSnapshot
    let tools: ToolRegistry
    let mcp: CapabilityStore?
    let skillHost: SkillToolHost
    let topicCoordinator: TopicCoordinator
    let clearStream: () -> Void
    /// After a batch finishes, offer tools again (ReAct) unless the loop cap is hit.
    let allowToolsAfterExecute: () -> Bool
    let continueTurn: (ModelTurn) async -> Void
    let preToolUseDecision: (String, String) async -> PreToolUseDecision
    let isToolApproved: (String, String) -> Bool
    let pauseForToolApproval: (AgentStep) async -> Void
    let pauseForToolRoundLimit: () async -> Void

    var events: [AgentEvent] { state.events }

    func activateSkill(named name: String) {
        state.activatedSkillNames.insert(name)
    }

    func commit(
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        mutate: (inout TaskRecord) -> Void = { _ in }
    ) async -> Bool {
        await taskStore.commit(
            appendEvents: appendEvents,
            deleteEventIDs: deleteEventIDs,
            mutate: mutate
        )
    }

    func persistPlanStepStatus(_ step: AgentStep, in plan: AgentPlan) async -> Bool {
        await taskStore.persistPlanStepStatus(step, in: plan)
    }

    func executeToolInvocation(name: String, argumentsJSON: String) async throws -> String {
        let policy = state.pathGuardPolicy
        let activated = skillHost.activatedSkillNames
        let enabled = skillHost.enabledSkills
        return try await taskStore.withActiveTaskContext {
            try await ToolInvocationDispatcher.execute(
                ToolInvocationRequest(
                    name: name,
                    argumentsJSON: argumentsJSON,
                    tools: tools,
                    mcp: mcp,
                    pathGuardPolicy: policy,
                    activatedSkillNames: activated,
                    enabledSkills: enabled,
                    skillHost: skillHost,
                    workPlanKind: state.activeTask?.workPlan?.kind,
                    modelSettings: modelSettings()
                )
            )
        }
    }

    func evaluatePreToolUse(name: String, argumentsJSON: String) async -> PreToolUseDecision {
        await preToolUseDecision(name, argumentsJSON)
    }

    func loadSkillName(from argumentsJSON: String) -> String? {
        SkillToolExecutor.loadSkillName(from: argumentsJSON)
    }

    func requestModelStreaming(includeTools: Bool) async throws -> ModelTurn {
        try await modelGateway.streamComplete(includeTools: includeTools)
    }

    func generateTopicIfNeeded() {
        topicCoordinator.generateTopicIfNeeded(for: state.activeTask)
    }

    func markFailed(_ message: String) async {
        await taskStore.markFailed(message)
    }

    func failDuringExecution(plan: AgentPlan, message: String) async {
        planProgress.update(plan)
        await taskStore.failDuringExecution(plan: plan, message: message)
    }
}
