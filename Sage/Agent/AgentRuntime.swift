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
    let streamingPlayback = StreamingPlayback()

    @ObservationIgnored let host: AgentHostSurface
    @ObservationIgnored let skillRecall: SkillRecallCoordinator
    @ObservationIgnored let modelGateway: AgentModelGateway
    @ObservationIgnored let topicCoordinator: TopicCoordinator
    @ObservationIgnored let taskStore: AgentTaskStore
    @ObservationIgnored let turns: TurnCoordinator
    @ObservationIgnored let streaming = StreamingTextPump()
    @ObservationIgnored let operations: SessionOperationGate
    @ObservationIgnored let lifecycle: SessionLifecycle
    @ObservationIgnored let router: CompositeTaskRouter

    @ObservationIgnored let tools: ToolRegistry
    @ObservationIgnored let taskRepository: any TaskRepository
    @ObservationIgnored let settings: ModelSettings
    @ObservationIgnored private(set) weak var skillCatalog: SkillCatalog?
    @ObservationIgnored private weak var mcpHub: CapabilityStore?
    /// Per-window skill tips / save jobs (owned by AgentSession).
    @ObservationIgnored let skills: SkillSessionController

    /// Called after skills are created/enhanced/deleted so AppState can refresh all windows.
    var onSkillsCatalogChanged: (() async -> Void)? {
        get { host.onSkillsCatalogChanged }
        set { host.onSkillsCatalogChanged = newValue }
    }

    // MARK: - Composite UI capabilities (state + plan + streaming)

    var isStreaming: Bool {
        if case .thinking = state.phase { return streamingPlayback.isActive }
        return false
    }

    var canRetryFailure: Bool {
        guard case .failed = state.phase else { return false }
        if state.activeTask?.pendingPlan != nil || planProgress.hasPlan { return true }
        return !state.events.isEmpty
    }

    var canStop: Bool {
        guard state.isBusy else { return false }
        switch state.phase {
        case .thinking, .executing:
            return true
        default:
            return false
        }
    }

    var canStartFresh: Bool {
        guard !state.isBusy else { return false }
        switch state.phase {
        case .thinking, .executing:
            return false
        case .awaitingConfirmation, .awaitingSkillChoice:
            return true
        case .idle, .completed, .failed:
            return state.activeTask?.events.isEmpty == false
                || state.contextHint != nil
                || state.forceFreshOnNextSubmit
        }
    }

    var blocksNewInput: Bool {
        if state.isBusy { return true }
        switch state.phase {
        case .thinking, .executing, .awaitingConfirmation, .awaitingSkillChoice:
            return true
        case .failed:
            return state.activeTask?.pendingPlan != nil || planProgress.hasPlan
        case .idle, .completed:
            return false
        }
    }

    var availableSlashCommandDefinitions: [SlashCommandDefinition] {
        host.availableSlashCommandDefinitions
    }

    let systemPrompt = """
    You are Sage, a native macOS agent that helps the user get work done on their Mac.
    Prefer using tools for real actions (files, clipboard, apps, notifications).
    Keep plans small and concrete. Expand ~ paths when useful.
    File and shell paths are sandboxed — stay inside the active sandbox described below.
    When rewriting text for the clipboard, use get_clipboard / set_clipboard.
    After tools run, you will see their results — then give a short clear summary of what happened.
    Reply in the same language the user uses.
    """

    init(
        settings: ModelSettings,
        tools: ToolRegistry,
        taskRepository: any TaskRepository,
        contextResolver: any TaskRouting = ContinuityTaskResolver(),
        skillCatalog: SkillCatalog? = nil,
        mcpHub: CapabilityStore? = nil,
        skills: SkillSessionController
    ) {
        let state = AgentSessionState()
        let planProgress = PlanProgress()
        self.state = state
        self.planProgress = planProgress
        self.settings = settings
        self.tools = tools
        self.taskRepository = taskRepository
        self.skillCatalog = skillCatalog
        self.mcpHub = mcpHub
        self.skills = skills

        weak let catalogRef = skillCatalog
        weak let mcpRef = mcpHub

        let continuity: ContinuityTaskResolver
        if let continuityResolver = contextResolver as? ContinuityTaskResolver {
            continuity = continuityResolver
        } else {
            continuity = ContinuityTaskResolver()
        }
        self.router = CompositeTaskRouter(continuity: continuity)

        let taskStore = AgentTaskStore(
            state: state,
            planProgress: planProgress,
            taskRepository: taskRepository,
            skills: skills
        )
        self.taskStore = taskStore

        let host = AgentHostSurface(
            state: state,
            taskStore: taskStore,
            skills: skills,
            settings: settings,
            tools: tools,
            skillCatalog: skillCatalog,
            mcpHub: mcpHub
        )
        self.host = host

        let skillRecall = SkillRecallCoordinator(
            state: state,
            skills: skills,
            skillCatalog: { catalogRef },
            taskStore: taskStore
        )
        self.skillRecall = skillRecall
        self.streaming.attach(playback: streamingPlayback)

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
        self.modelGateway = modelGateway

        let topicCoordinator = TopicCoordinator(
            state: state,
            taskRepository: taskRepository
        )
        self.topicCoordinator = topicCoordinator
        taskStore.bind(topicCoordinator: topicCoordinator, skillRecall: skillRecall)

        let operations = SessionOperationGate(state: state)
        self.operations = operations

        let lifecycle = SessionLifecycle(
            state: state,
            planProgress: planProgress,
            taskRepository: taskRepository,
            skillCatalog: { catalogRef },
            skills: skills,
            skillRecall: skillRecall,
            modelGateway: modelGateway,
            taskStore: taskStore,
            operations: operations
        )
        self.lifecycle = lifecycle

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
            topicCoordinator: topicCoordinator
        )
        self.turns = turns

        skills.attach(runtime: self)
        skillRecall.bind(skillHost: { [weak host] in host })
        turns.bind(
            slashHost: host,
            confirmPlan: { [weak self] in await self?.confirmPendingPlanUnlocked() },
            handleStop: { [weak self] plan in
                guard let self else { return }
                await PlanExecutor.handleStop(plan: plan, services: self.makePlanServices())
            }
        )
    }

    private func makePlanServices() -> PlanServices {
        PlanServices(
            state: state,
            planProgress: planProgress,
            taskStore: taskStore,
            skillRecall: skillRecall,
            modelGateway: modelGateway,
            tools: tools,
            mcp: mcpHub,
            skillHost: host,
            topicCoordinator: topicCoordinator,
            clearStream: { [weak self] in self?.streaming.clear() }
        )
    }

    /// Boots this window's session. Pass `project` for a project window; `nil` for General.
    /// - Parameter reloadCatalog: When false, skip skill rescan (caller already applied a shared scan).
    func bootstrap(project: ProjectRecord? = nil, reloadCatalog: Bool = true) async {
        await lifecycle.bootstrap(project: project, reloadCatalog: reloadCatalog)
    }

    func prepareForWindowClose() async {
        await lifecycle.prepareForWindowClose()
    }

    func broadcastSkillsCatalogChange() async {
        await host.broadcastSkillsCatalogChange()
    }

    func applySkillExtractionPhase(_ phase: AgentPhase) {
        state.phase = phase
    }

    func reportFailure(_ message: String) {
        state.phase = .failed(message: message)
    }

    func applyRecentProjects(_ projects: [ProjectRecord]) {
        state.recentProjects = projects
    }

    @discardableResult
    func startFresh() async -> UUID? {
        guard operations.begin() else { return nil }
        defer { operations.end() }

        if case .awaitingConfirmation = state.phase {
            guard await performCancelPendingPlan() else { return nil }
        } else if case .awaitingSkillChoice = state.phase {
            await lifecycle.abandonAwaitingSkillChoice(
                reason: "Cancelled skill choice — started a new task."
            )
        } else if let plan = state.activeTask?.pendingPlan ?? planProgress.plan {
            planProgress.replace(plan)
            state.phase = .awaitingConfirmation
            guard await performCancelPendingPlan() else { return nil }
        }

        state.forceFreshOnNextSubmit = false
        state.clearThreadRoutingNotices()
        return await taskStore.beginNewTask(relatedTo: [])
    }

    func dismissContextHint() {
        state.contextHint = nil
        state.forceFreshOnNextSubmit = true
    }

    func dismissTopicDriftOffer() {
        state.dismissTopicDriftOffer()
    }

    func acceptTopicDriftOffer() async {
        guard !state.isAcceptingTopicDrift else { return }
        guard let offer = state.topicDriftOffer else { return }
        guard offer.taskID == state.activeTaskID else {
            state.clearTopicDriftOffer()
            return
        }

        state.isAcceptingTopicDrift = true
        defer { state.isAcceptingTopicDrift = false }

        if state.isBusy {
            operations.requestStop()
            await operations.cancelInFlight()
        }

        guard operations.begin() else { return }
        defer { operations.end() }

        if case .awaitingSkillChoice = state.phase {
            skills.tips.dismissChoose()
            state.phase = .idle
        }

        streaming.clear()
        guard let result = await taskStore.splitOffTurn(from: offer.triggeringUserEventID) else {
            return
        }

        guard result.needsModelTurn else { return }
        state.phase = .thinking
        let ready = await skillRecall.prepareSkillsForTurn(query: result.userQuery)
        guard ready else { return }
        await turns.runModelTurn()
    }

    func stop() {
        guard canStop else { return }
        operations.requestStop()
    }

    func eraseAllData() async -> Bool {
        await lifecycle.eraseAllData()
    }

    func syncGlobalFocusPointer() async {
        await lifecycle.syncGlobalFocusPointer()
    }

    func retryLastFailure() async {
        guard case .failed = state.phase else { return }
        _ = await operations.run { await self.turns.performRetry() }
    }

    @discardableResult
    func submit(_ userText: String) async -> Bool {
        await operations.runAccepted { await self.turns.performSubmit(userText) }
    }

    func confirmPendingPlan() async {
        _ = await operations.run { await self.confirmPendingPlanUnlocked() }
    }

    func cancelPendingPlan() async {
        guard operations.begin() else { return }
        defer { operations.end() }
        _ = await performCancelPendingPlan()
    }

    func resetPhaseToIdle() {
        if case .completed = state.phase { state.phase = .idle }
        if case .failed = state.phase, state.activeTask?.pendingPlan == nil, !planProgress.hasPlan {
            state.phase = .idle
        }
    }

    func dismissFailure() async {
        guard case .failed = state.phase else { return }
        if let plan = state.activeTask?.pendingPlan ?? planProgress.plan {
            guard operations.begin() else { return }
            defer { operations.end() }
            planProgress.replace(plan)
            state.phase = .awaitingConfirmation
            _ = await performCancelPendingPlan()
            return
        }
        state.phase = .idle
    }

    func runModelTurn() async {
        await turns.runModelTurn()
    }

    func selectSkillActivation(named name: String) async {
        guard case .awaitingSkillChoice(let choice) = state.phase else { return }
        guard choice.candidates.contains(where: { $0.name == name }) else { return }

        _ = await operations.run {
            self.skills.tips.dismissChoose()
            self.skills.enqueueConsolidateIfNeeded(candidates: choice.candidates)
            self.state.phase = .thinking
            await self.skillRecall.loadSkillsByName([name])
            await self.skillRecall.refreshCatalogWithoutRematch(query: choice.queryText)
            await self.runModelTurn()
        }
    }

    func skipSkillActivation() async {
        guard case .awaitingSkillChoice(let choice) = state.phase else { return }

        _ = await operations.run {
            self.skills.tips.dismissChoose()
            self.skills.enqueueConsolidateIfNeeded(candidates: choice.candidates)
            self.state.phase = .thinking
            await self.runModelTurn()
        }
    }

    @discardableResult
    func prepareSkillsForTurn(query: String) async -> Bool {
        await skillRecall.prepareSkillsForTurn(query: query)
    }

    func noteSkillsActivated(_ names: Set<String>) {
        state.activatedSkillNames.formUnion(names)
    }

    func confirmPendingPlanUnlocked() async {
        guard case .awaitingConfirmation = state.phase else { return }
        let plan = planProgress.plan ?? state.activeTask?.pendingPlan
        guard let initialPlan = plan else { return }
        await PlanExecutor.execute(initialPlan: initialPlan, services: makePlanServices())
    }

    @discardableResult
    private func performCancelPendingPlan() async -> Bool {
        guard case .awaitingConfirmation = state.phase else { return false }
        return await PlanExecutor.cancelPendingPlan(services: makePlanServices())
    }

    // MARK: - Task store façades used by UI / AppState

    @discardableResult
    func beginNewTask(relatedTo relatedTaskIDs: [UUID] = []) async -> UUID? {
        await taskStore.beginNewTask(relatedTo: relatedTaskIDs)
    }

    func activateTask(_ id: UUID) async {
        await taskStore.activateTask(id)
    }

    @discardableResult
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
}
