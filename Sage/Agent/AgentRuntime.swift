//
//  AgentRuntime.swift
//  Sage
//
//  Thin façade over AgentSessionState + coordinators. UI should observe
//  `state` and `planProgress` directly (not computed projections).
//

import Foundation

@MainActor
@Observable
final class AgentRuntime {
    let state: AgentSessionState
    let planProgress: PlanProgress
    /// Streaming tokens live here — not on session state — so workspace chrome
    /// / composer do not rebuild on every SSE chunk.
    let streamingPlayback: StreamingPlayback

    @ObservationIgnored let host: AgentHostSurface
    @ObservationIgnored let skillRecall: SkillRecallCoordinator
    @ObservationIgnored let modelGateway: AgentModelGateway
    @ObservationIgnored let topicCoordinator: TopicCoordinator
    @ObservationIgnored let taskStore: AgentTaskStore
    @ObservationIgnored let turns: TurnCoordinator
    @ObservationIgnored let streaming: StreamingTextPump
    @ObservationIgnored let operations: SessionOperationGate
    @ObservationIgnored let lifecycle: SessionLifecycle
    @ObservationIgnored let router: CompositeTaskRouter
    @ObservationIgnored let contextCompactor: ContextCompactor

    @ObservationIgnored let tools: ToolRegistry
    @ObservationIgnored let taskRepository: any TaskRepository
    @ObservationIgnored let settings: ModelSettings
    @ObservationIgnored private(set) weak var skillCatalog: SkillCatalog?
    @ObservationIgnored weak var mcpHub: CapabilityStore?
    /// Per-window skill tips / save jobs (owned by AgentSession).
    @ObservationIgnored let skills: SkillSessionController

    /// Called after skills are created/enhanced/deleted so AppState can refresh all windows.
    var onSkillsCatalogChanged: (() async -> Void)? {
        get { host.onSkillsCatalogChanged }
        set { host.onSkillsCatalogChanged = newValue }
    }

    /// Window sessions use this so a first-run schedule can freeze after the user confirms.
    var onTaskSettled: ((UUID, WorkPlan?, AgentTaskSettlement) async -> Void)?

    static let defaultSystemPrompt = """
    You are Sage, a native macOS agent that helps the user get work done on their Mac.
    Prefer using tools for real actions (files, clipboard, apps, notifications).
    A separate planner already produced the work plan — follow it. Use tools as you go.
    Expand ~ paths when useful. Follow Active sandbox and Confirmed work plan. \
    Runtime lists live skills, MCP, and todos.
    Prefer file tools for reads and writes. After tools run, you will see their results — \
    then continue or give a short summary.
    For multi-step act work, track remaining steps with manage_todo_list — do not rewrite the work plan.
    Reply in the same language the user uses.
    """

    let systemPrompt = AgentRuntime.defaultSystemPrompt

    init(
        settings: ModelSettings,
        tools: ToolRegistry,
        taskRepository: any TaskRepository,
        contextResolver: any TaskRouting = ContinuityTaskResolver(),
        skillCatalog: SkillCatalog? = nil,
        mcpHub: CapabilityStore? = nil,
        skills: SkillSessionController
    ) {
        let streaming = StreamingTextPump()
        let streamingPlayback = StreamingPlayback()
        let graph = AgentSessionGraph.assemble(
            AgentSessionGraphRequest(
                settings: settings,
                tools: tools,
                taskRepository: taskRepository,
                contextResolver: contextResolver,
                skillCatalog: skillCatalog,
                mcpHub: mcpHub,
                skills: skills,
                systemPrompt: Self.defaultSystemPrompt,
                streaming: streaming,
                streamingPlayback: streamingPlayback
            )
        )
        self.state = graph.state
        self.planProgress = graph.planProgress
        self.streamingPlayback = streamingPlayback
        self.streaming = streaming
        self.settings = settings
        self.tools = tools
        self.taskRepository = taskRepository
        self.skillCatalog = skillCatalog
        self.mcpHub = mcpHub
        self.skills = skills
        self.router = graph.router
        self.taskStore = graph.taskStore
        self.host = graph.host
        self.skillRecall = graph.skillRecall
        self.modelGateway = graph.modelGateway
        self.topicCoordinator = graph.topicCoordinator
        self.operations = graph.operations
        self.lifecycle = graph.lifecycle
        self.turns = graph.turns
        self.contextCompactor = graph.contextCompactor

        skills.attach(runtime: self)
        bindSessionCallbacks()
    }
}
