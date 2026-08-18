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

    static func assemble(
        settings: ModelSettings,
        tools: ToolRegistry,
        taskRepository: any TaskRepository,
        contextResolver: any TaskRouting,
        skillCatalog: SkillCatalog?,
        mcpHub: CapabilityStore?,
        skills: SkillSessionController,
        systemPrompt: String,
        streaming: StreamingTextPump,
        streamingPlayback: StreamingPlayback
    ) -> AgentSessionGraph {
        let state = AgentSessionState()
        let planProgress = PlanProgress()
        weak let catalogRef = skillCatalog
        weak let mcpRef = mcpHub

        let continuity = (contextResolver as? ContinuityTaskResolver) ?? ContinuityTaskResolver()
        let router = CompositeTaskRouter(continuity: continuity)
        let taskStore = AgentTaskStore(
            state: state,
            planProgress: planProgress,
            taskRepository: taskRepository,
            skills: skills
        )
        let host = AgentHostSurface(
            state: state,
            taskStore: taskStore,
            skills: skills,
            settings: settings,
            tools: tools,
            skillCatalog: skillCatalog,
            mcpHub: mcpHub
        )
        let skillRecall = SkillRecallCoordinator(
            state: state,
            skills: skills,
            skillCatalog: { catalogRef },
            taskStore: taskStore
        )
        streaming.attach(playback: streamingPlayback)

        let modelGateway = AgentModelGateway(
            state: state,
            settings: settings,
            tools: tools,
            systemPrompt: systemPrompt,
            skillRecall: skillRecall,
            skillCatalog: { catalogRef },
            mcpToolDefinitions: { mcpRef?.mcpToolDefinitions() ?? [] },
            taskRepository: taskRepository,
            projectPromptAppendix: {
                SessionLifecycle.projectPromptAppendix(for: state.focusedProject)
            },
            streaming: streaming
        )
        let topicCoordinator = TopicCoordinator(
            state: state,
            taskRepository: taskRepository
        )
        taskStore.bind(topicCoordinator: topicCoordinator, skillRecall: skillRecall)

        let operations = SessionOperationGate(state: state)
        let lifecycle = SessionLifecycle(
            state: state,
            planProgress: planProgress,
            taskRepository: taskRepository,
            skillCatalog: { catalogRef },
            skills: skills,
            modelGateway: modelGateway,
            taskStore: taskStore,
            operations: operations
        )
        let turns = TurnCoordinator(
            state: state,
            planProgress: planProgress,
            taskStore: taskStore,
            router: router,
            skillRecall: skillRecall,
            modelGateway: modelGateway,
            settings: settings,
            skillCatalog: { catalogRef },
            workspaceSnapshot: { lifecycle.currentWorkspaceSnapshot() },
            streaming: streaming,
            topicCoordinator: topicCoordinator,
            skills: skills
        )
        skillRecall.bind(skillHost: { [weak host] in host })

        return AgentSessionGraph(
            state: state,
            planProgress: planProgress,
            router: router,
            taskStore: taskStore,
            host: host,
            skillRecall: skillRecall,
            modelGateway: modelGateway,
            topicCoordinator: topicCoordinator,
            operations: operations,
            lifecycle: lifecycle,
            turns: turns
        )
    }
}
