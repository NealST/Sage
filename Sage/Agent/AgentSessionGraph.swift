//
//  AgentSessionGraph.swift
//  Sage
//
//  Wires session collaborators. AgentRuntime stays a UI façade and binds
//  self-referential callbacks after this graph exists.
//

import Foundation

@MainActor
struct AgentSessionGraph {
    let state: AgentSessionState
    let planProgress: PlanProgress
    let router: CompositeTaskRouter
    let taskStore: AgentTaskStore
    let host: AgentHostSurface
    let skillRecall: SkillRecallCoordinator
    let modelGateway: AgentModelGateway
    let topicCoordinator: TopicCoordinator
    let operations: SessionOperationGate
    let lifecycle: SessionLifecycle
    let turns: TurnCoordinator
    let contextCompactor: ContextCompactor

    static func assemble(_ request: AgentSessionGraphRequest) -> Self {
        let state = AgentSessionState()
        let planProgress = PlanProgress()
        weak let catalogRef = request.skillCatalog
        weak let mcpRef = request.mcpHub
        let continuity = (request.contextResolver as? ContinuityTaskResolver) ?? ContinuityTaskResolver()
        let router = CompositeTaskRouter(continuity: continuity)
        let taskStore = AgentTaskStore(
            state: state,
            planProgress: planProgress,
            taskRepository: request.taskRepository,
            skills: request.skills
        )
        let host = makeHost(request, state: state, taskStore: taskStore)
        let skillRecall = SkillRecallCoordinator(
            state: state,
            skills: request.skills,
            skillCatalog: { catalogRef },
            taskStore: taskStore
        )
        request.streaming.attach(playback: request.streamingPlayback)
        return makeSessionCore(
            SessionCoreParts(
                request: request,
                state: state,
                planProgress: planProgress,
                router: router,
                taskStore: taskStore,
                host: host,
                skillRecall: skillRecall,
                catalogRef: catalogRef,
                mcpRef: mcpRef
            )
        )
    }

    struct SessionCoreParts {
        var request: AgentSessionGraphRequest
        var state: AgentSessionState
        var planProgress: PlanProgress
        var router: CompositeTaskRouter
        var taskStore: AgentTaskStore
        var host: AgentHostSurface
        var skillRecall: SkillRecallCoordinator
        var catalogRef: SkillCatalog?
        var mcpRef: CapabilityStore?
    }

    static func makeSessionCore(_ parts: SessionCoreParts) -> Self {
        let context = makeContextLayer(parts)
        let operations = SessionOperationGate(state: parts.state)
        let lifecycle = makeLifecycle(parts, context: context, operations: operations)
        let turns = makeTurns(
            TurnsParts(
                request: parts.request,
                state: parts.state,
                planProgress: parts.planProgress,
                taskStore: parts.taskStore,
                router: parts.router,
                skillRecall: parts.skillRecall,
                modelGateway: context.modelGateway,
                catalogRef: parts.catalogRef,
                lifecycle: lifecycle,
                topicCoordinator: context.topicCoordinator
            )
        )
        parts.skillRecall.bind { [weak host = parts.host] in host }
        return assembled(parts, context: context, operations: operations, lifecycle: lifecycle, turns: turns)
    }

    struct ContextLayer {
        var modelGateway: AgentModelGateway
        var topicCoordinator: TopicCoordinator
        var contextCompactor: ContextCompactor
    }

    static func makeContextLayer(_ parts: SessionCoreParts) -> ContextLayer {
        let modelGateway = makeModelGateway(
            parts.request,
            state: parts.state,
            skillRecall: parts.skillRecall,
            catalogRef: parts.catalogRef,
            mcpRef: parts.mcpRef
        )
        let topicCoordinator = TopicCoordinator(
            state: parts.state,
            taskRepository: parts.request.taskRepository
        )
        let contextCompactor = ContextCompactor(
            state: parts.state,
            taskStore: parts.taskStore,
            modelGateway: modelGateway,
            settings: parts.request.settings
        )
        modelGateway.bind(compact: contextCompactor)
        parts.taskStore.bind(
            topicCoordinator: topicCoordinator,
            skillRecall: parts.skillRecall,
            contextCompactor: contextCompactor
        )
        return ContextLayer(
            modelGateway: modelGateway,
            topicCoordinator: topicCoordinator,
            contextCompactor: contextCompactor
        )
    }

    static func makeLifecycle(
        _ parts: SessionCoreParts,
        context: ContextLayer,
        operations: SessionOperationGate
    ) -> SessionLifecycle {
        SessionLifecycle(
            state: parts.state,
            planProgress: parts.planProgress,
            taskRepository: parts.request.taskRepository,
            skillCatalog: { parts.catalogRef },
            skills: parts.request.skills,
            modelGateway: context.modelGateway,
            taskStore: parts.taskStore,
            operations: operations
        )
    }

    static func assembled(
        _ parts: SessionCoreParts,
        context: ContextLayer,
        operations: SessionOperationGate,
        lifecycle: SessionLifecycle,
        turns: TurnCoordinator
    ) -> Self {
        Self(
            state: parts.state,
            planProgress: parts.planProgress,
            router: parts.router,
            taskStore: parts.taskStore,
            host: parts.host,
            skillRecall: parts.skillRecall,
            modelGateway: context.modelGateway,
            topicCoordinator: context.topicCoordinator,
            operations: operations,
            lifecycle: lifecycle,
            turns: turns,
            contextCompactor: context.contextCompactor
        )
    }

    static func makeHost(
        _ request: AgentSessionGraphRequest,
        state: AgentSessionState,
        taskStore: AgentTaskStore
    ) -> AgentHostSurface {
        AgentHostSurface(
            state: state,
            taskStore: taskStore,
            skills: request.skills,
            settings: request.settings,
            tools: request.tools,
            skillCatalog: request.skillCatalog,
            mcpHub: request.mcpHub
        )
    }

    static func makeModelGateway(
        _ request: AgentSessionGraphRequest,
        state: AgentSessionState,
        skillRecall: SkillRecallCoordinator,
        catalogRef: SkillCatalog?,
        mcpRef: CapabilityStore?
    ) -> AgentModelGateway {
        AgentModelGateway(
            state: state,
            settings: request.settings,
            tools: request.tools,
            systemPrompt: request.systemPrompt,
            skillRecall: skillRecall,
            skillCatalog: { catalogRef },
            mcpToolDefinitions: { mcpRef?.mcpToolDefinitions() ?? [] },
            taskRepository: request.taskRepository,
            projectPromptAppendix: {
                SessionLifecycle.projectPromptAppendix(for: state.focusedProject)
            },
            streaming: request.streaming
        )
    }

    struct TurnsParts {
        var request: AgentSessionGraphRequest
        var state: AgentSessionState
        var planProgress: PlanProgress
        var taskStore: AgentTaskStore
        var router: CompositeTaskRouter
        var skillRecall: SkillRecallCoordinator
        var modelGateway: AgentModelGateway
        var catalogRef: SkillCatalog?
        var lifecycle: SessionLifecycle
        var topicCoordinator: TopicCoordinator
    }

    static func makeTurns(_ parts: TurnsParts) -> TurnCoordinator {
        TurnCoordinator(
            state: parts.state,
            planProgress: parts.planProgress,
            taskStore: parts.taskStore,
            router: parts.router,
            skillRecall: parts.skillRecall,
            modelGateway: parts.modelGateway,
            settings: parts.request.settings,
            skillCatalog: { parts.catalogRef },
            workspaceSnapshot: { parts.lifecycle.currentWorkspaceSnapshot() },
            streaming: parts.request.streaming,
            topicCoordinator: parts.topicCoordinator,
            skills: parts.request.skills
        )
    }
}
