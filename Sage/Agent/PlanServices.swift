//
//  PlanServices.swift
//  Sage
//
//  Dependency bag for PlanExecutor — no Host protocol.
//

import Foundation

@MainActor
struct PlanServices {
    let state: AgentSessionState
    let planProgress: PlanProgress
    let taskStore: AgentTaskStore
    let skillRecall: SkillRecallCoordinator
    let modelGateway: AgentModelGateway
    let tools: ToolRegistry
    let mcp: CapabilityStore?
    let skillHost: SkillToolHost
    let topicCoordinator: TopicCoordinator
    let clearStream: () -> Void

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
        try await ToolInvocationDispatcher.execute(
            name: name,
            argumentsJSON: argumentsJSON,
            tools: tools,
            mcp: mcp,
            pathGuardPolicy: state.pathGuardPolicy,
            skillHost: skillHost
        )
    }

    @discardableResult
    func prepareSkillsForTurn(query: String) async -> Bool {
        await skillRecall.prepareSkillsForTurn(query: query)
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
