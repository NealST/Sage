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

    /// Window sessions use this so a first-run schedule can freeze after the user confirms.
    var onTaskSettled: ((UUID, WorkPlan?, AgentTaskSettlement) async -> Void)?

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
        if state.isAcceptingTopicDrift { return false }
        // Never fork or archive while a turn is in flight — tools may already
        // have mutated the Mac.
        guard !state.isBusy else { return false }
        if state.topicDriftOffer != nil { return true }
        switch state.phase {
        case .thinking, .executing:
            return false
        case .awaitingConfirmation:
            return true
        case .idle, .completed, .failed:
            return state.activeTask?.events.isEmpty == false
                || state.contextHint != nil
                || state.forceFreshOnNextSubmit
        }
    }

    /// Strategy card vs in-flight tool batch. Shared by transcript chrome and confirm APIs.
    var turnChrome: AgentTurnChrome? {
        AgentTurnChrome.resolve(
            phase: state.phase,
            hasWorkPlan: state.activeTask?.workPlan != nil,
            hasToolBatch: planProgress.plan != nil || state.activeTask?.pendingPlan != nil
        )
    }

    var blocksNewInput: Bool {
        if state.isBusy { return true }
        switch state.phase {
        case .thinking, .executing, .awaitingConfirmation:
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
    A separate planner already produced the work plan — follow it. Use tools as you go;
    do not wait for the user to approve each call. Expand ~ paths when useful.
    File tools stay inside the active sandbox described below.
    Shell working directory is sandboxed; the command string itself can still cd or touch other paths. Prefer file tools for reads and writes.
    When rewriting text for the clipboard, use get_clipboard / set_clipboard.
    After tools run, you will see their results — then continue or give a short summary.
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
            topicCoordinator: topicCoordinator,
            skills: skills
        )
        self.turns = turns

        skills.attach(runtime: self)
        skillRecall.bind(skillHost: { [weak host] in host })
        turns.onTaskSettled = { [weak self] id, plan, outcome in
            await self?.onTaskSettled?(id, plan, outcome)
        }
        taskStore.onTaskFailed = { [weak self] id, message in
            guard let self else { return }
            let plan = self.state.activeTask?.id == id ? self.state.activeTask?.workPlan : nil
            await self.onTaskSettled?(id, plan, .failed(message))
        }
        turns.bind(
            slashHost: host,
            executeToolBatch: { [weak self] in await self?.executeCurrentPlanUnlocked() },
            handleStop: { [weak self] plan in
                guard let self else { return }
                await ToolBatchExecutor.handleStop(plan: plan, services: self.makeExecuteServices())
            }
        )
    }

    private func makeExecuteServices() -> ExecuteServices {
        ExecuteServices(
            state: state,
            planProgress: planProgress,
            taskStore: taskStore,
            modelGateway: modelGateway,
            tools: tools,
            mcp: mcpHub,
            skillHost: host,
            topicCoordinator: topicCoordinator,
            clearStream: { [weak self] in self?.streaming.clear() },
            allowToolsAfterExecute: { [weak self] in
                self?.turns.canOfferMoreTools ?? false
            },
            continueTurn: { [weak self] turn in
                await self?.turns.handleTurn(turn)
            }
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
        guard canStartFresh else { return nil }
        if state.topicDriftOffer != nil {
            await acceptTopicDriftOffer()
            return state.activeTaskID
        }

        guard operations.begin() else { return nil }
        defer { operations.end() }

        if case .awaitingConfirmation = state.phase {
            guard await performCancelPendingPlan() else { return nil }
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
        guard !state.isBusy else { return }
        guard let offer = state.topicDriftOffer else { return }
        guard offer.taskID == state.activeTaskID else {
            state.clearTopicDriftOffer()
            return
        }

        state.isAcceptingTopicDrift = true
        defer { state.isAcceptingTopicDrift = false }

        _ = await operations.run {
            self.skills.tips.dismissChoose()
            self.streaming.clear()
            guard let result = await self.taskStore.splitOffTurn(from: offer.triggeringUserEventID) else {
                return
            }

            guard result.needsModelTurn else { return }
            self.state.phase = .thinking
            let ready = await self.skillRecall.prepareSkillsForTurn(query: result.userQuery)
            guard ready else { return }
            await self.turns.runModelTurn()
        }
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

    func performScheduledRun(prompt: String, frozenPlan: WorkPlan?) async {
        _ = await operations.run {
            await self.turns.performScheduledRun(prompt: prompt, frozenPlan: frozenPlan)
        }
    }

    @discardableResult
    func spawnScheduledTask(projectID: UUID?, summary: String?, originScheduleID: UUID?) async -> UUID? {
        await taskStore.spawnScheduledTask(
            projectID: projectID,
            summary: summary,
            originScheduleID: originScheduleID
        )
    }

    func confirmPendingPlan() async {
        switch turnChrome {
        case .workPlan:
            await confirmWorkPlan()
        case .toolBatch, .none:
            await confirmToolBatch()
        }
    }

    func confirmWorkPlan() async {
        guard turnChrome == .workPlan else { return }
        _ = await operations.run { await self.turns.startExecution() }
    }

    func confirmToolBatch() async {
        _ = await operations.run { await self.executeCurrentPlanUnlocked() }
    }

    func cancelPendingPlan() async {
        guard operations.begin() else { return }
        defer { operations.end() }
        let taskID = state.activeTaskID
        let cancelled = await performCancelPendingPlan()
        if cancelled, let taskID {
            await onTaskSettled?(taskID, nil, .cancelled)
        }
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
            let taskID = state.activeTaskID
            if await performCancelPendingPlan(), let taskID {
                await onTaskSettled?(taskID, nil, .cancelled)
            }
            return
        }
        state.phase = .idle
    }

    func runModelTurn() async {
        await turns.runModelTurn()
    }

    func selectSkillActivation(named name: String) async {
        guard let choice = skills.tips.choosePrompt,
              choice.candidates.contains(where: { $0.name == name })
        else { return }

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
        guard let choice = skills.tips.choosePrompt else { return }

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

    func executeCurrentPlanUnlocked() async {
        let plan = planProgress.plan ?? state.activeTask?.pendingPlan
        guard let initialPlan = plan else { return }
        await ToolBatchExecutor.execute(initialPlan: initialPlan, services: makeExecuteServices())
    }

    @discardableResult
    private func performCancelPendingPlan() async -> Bool {
        guard case .awaitingConfirmation = state.phase else { return false }
        return await ToolBatchExecutor.cancelPendingPlan(services: makeExecuteServices())
    }

    // MARK: - Task store façades used by UI / AppState

    @discardableResult
    func beginNewTask(relatedTo relatedTaskIDs: [UUID] = []) async -> UUID? {
        await taskStore.beginNewTask(relatedTo: relatedTaskIDs)
    }

    func activateTask(_ id: UUID) async {
        guard id != state.activeTaskID else { return }
        if state.isBusy {
            await operations.cancelInFlight()
        }
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
