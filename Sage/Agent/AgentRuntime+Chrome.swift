//
//  AgentRuntime+Chrome.swift
//  Sage
//

import Foundation

extension AgentRuntime {
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
            hasToolBatch: planProgress.plan != nil || state.activeTask?.pendingPlan != nil,
            pendingPrompt: state.pendingPrompt
        )
    }

    var blocksNewInput: Bool {
        switch state.phase {
        case .failed:
            return state.activeTask?.pendingPlan != nil || planProgress.hasPlan

        default:
            return false
        }
    }

    var availableSlashCommandDefinitions: [SlashCommandDefinition] {
        host.availableSlashCommandDefinitions
    }

    func bindSessionCallbacks() {
        turns.onTaskSettled = { [weak self] id, plan, outcome in
            await self?.onTaskSettled?(id, plan, outcome)
        }
        taskStore.onTaskFailed = { [weak self] id, message in
            guard let self else { return }
            let plan = self.state.activeTask?.id == id ? self.state.activeTask?.workPlan : nil
            await self.onTaskSettled?(id, plan, .failed(message))
        }
        taskStore.onActiveTaskChanged = { [weak self] in
            self?.turns.adoptActiveTask()
        }
        taskStore.onTaskClosed = { [weak self] id in
            self?.turns.dropTurnLoop(for: id)
        }
        operations.onBecameIdle = { [weak self] in
            await self?.drainQueuedTurns()
        }
        turns.bind(
            slashHost: host,
            executeToolBatch: { [weak self] retryFailed in
                await self?.executeCurrentPlanUnlocked(retryFailedSteps: retryFailed)
            },
            handleStop: { [weak self] plan in
                guard let self else { return }
                await ToolBatchExecutor.handleStop(plan: plan, services: self.makeExecuteServices())
            }
        )
    }

    func makeExecuteServices() -> ExecuteServices {
        ExecuteServices(
            state: state,
            planProgress: planProgress,
            taskStore: taskStore,
            modelGateway: modelGateway,
            modelSettings: { [settings] in settings.snapshot(for: .execute) },
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
            },
            preToolUseDecision: { [weak self] name, args in
                await self?.preToolUseDecision(name: name, argumentsJSON: args)
                    ?? .deny("The agent session is no longer available.")
            },
            isToolApproved: { [weak self] name, args in
                guard let self else { return false }
                return self.state.sessionAllowlist.contains(
                    name: name,
                    argumentsJSON: args,
                    policy: self.state.pathGuardPolicy,
                    scopeID: self.state.authorizationScopeID,
                    skills: self.host.catalogSkills,
                    mcpTools: self.mcpHub?.mcpTools ?? []
                )
            },
            isHookApproved: { [weak self] name, args, hookIdentity in
                guard let self else { return false }
                return self.state.sessionAllowlist.containsHookApproval(
                    name: name,
                    argumentsJSON: args,
                    hookIdentity: hookIdentity,
                    scopeID: self.state.authorizationScopeID
                )
            },
            pauseForToolApproval: { [weak self] _ in
                self?.state.enterAwaitingConfirmation()
            },
            pauseForToolRoundLimit: { [weak self] in
                await self?.turns.pauseForToolRoundLimit()
            }
        )
    }

    /// Boots this window's session. Pass `project` for a project window; `nil` for General.
    /// - Parameter reloadCatalog: When false, skip skill rescan (caller already applied a shared scan).
    func bootstrap(project: ProjectRecord? = nil, reloadCatalog: Bool = true) async {
        await lifecycle.bootstrap(project: project, reloadCatalog: reloadCatalog)
        turns.adoptActiveTask()
    }

    func prepareForWindowClose() async {
        contextCompactor.cancel()
        await lifecycle.prepareForWindowClose()
    }

    func broadcastSkillsCatalogChange() async {
        await host.broadcastSkillsCatalogChange()
    }

    func preToolUseDecision(name: String, argumentsJSON: String) async -> PreToolUseDecision {
        let activated = host.enabledSkills.filter { skill in
            state.activatedSkillNames.contains(skill.name)
        }
        let decision = await PreToolUseHookEvaluator.shared.evaluate(
            toolName: name,
            argumentsJSON: argumentsJSON,
            projectRoot: state.focusedProject?.rootURL,
            activatedSkills: activated
        )
        return decision
    }

    func applySkillExtractionPhase(_ phase: AgentPhase) {
        state.applyHostPhase(phase)
    }

    func reportFailure(_ message: String) {
        state.enterFailed(message: message)
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
            state.enterAwaitingConfirmation()
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
            self.state.enterThinking()
            let ready = self.skillRecall.prepareSkillsForTurn(query: result.userQuery)
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

    func freezeConfirmationActions() {
        guard case .awaitingConfirmation = state.phase else { return }
        state.freezeConfirmationActions()
    }

    func unfreezeConfirmationActions() {
        state.unfreezeConfirmationActions()
    }

    @discardableResult
    func submit(_ userText: String, attachments: [MessageAttachment] = []) async -> Bool {
        if state.isBusy {
            state.turnInput.offer = QueuedUserTurn(text: userText, attachments: attachments)
            return true
        }
        freezeConfirmationActions()
        return await operations.runAccepted {
            await self.turns.performSubmit(userText, attachments: attachments)
        }
    }

    func queueTurnInterrupt() {
        state.turnInput.enqueueOffer()
    }

    func dismissTurnInterrupt() {
        state.turnInput.offer = nil
    }

    func steerTurnInterrupt() async {
        guard let offer = state.turnInput.offer else { return }
        state.turnInput.offer = nil
        state.turnInput.pendingSteer = offer
        await operations.cancelInFlight()
        guard await turns.persistSteerTurn(offer) else {
            state.turnInput.pendingSteer = nil
            return
        }
        _ = await operations.run { await self.turns.continueAfterSteer() }
    }

    func drainQueuedTurns() async {
        guard state.turnInput.pendingSteer == nil, !state.isBusy else { return }
        if case .awaitingConfirmation = state.phase { return }
        if state.pendingPrompt != nil { return }
        guard let next = state.turnInput.popNext() else { return }
        _ = await operations.runAccepted {
            await self.turns.performSubmit(next.text, attachments: next.attachments)
        }
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

        case .toolBatch:
            await confirmToolBatch()

        case .toolRoundLimit:
            await confirmToolRoundLimit()

        case .toolApproval:
            await confirmToolApproval(scope: .task)

        case .reviewFailed:
            await retryFailedReview()

        case .none:
            break
        }
    }

    func retryFailedReview() async {
        guard !state.shouldDisableConfirmationActions else { return }
        guard turnChrome == .reviewFailed else { return }
        _ = await operations.run { await self.turns.retryFailedReview() }
    }

    func acceptFailedReview() async {
        guard !state.shouldDisableConfirmationActions else { return }
        guard turnChrome == .reviewFailed else { return }
        _ = await operations.run { await self.turns.acceptFailedReview() }
    }
}
