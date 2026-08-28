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

    func bindSessionCallbacks() {
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
                return self.state.sessionAllowlist.consumeApproval(
                    name: name,
                    argumentsJSON: args,
                    policy: self.state.pathGuardPolicy,
                    scopeID: self.state.authorizationScopeID,
                    skills: self.host.enabledSkills,
                    mcpTools: self.mcpHub?.mcpTools ?? []
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

    @discardableResult
    func submit(_ userText: String, attachments: [MessageAttachment] = []) async -> Bool {
        await operations.runAccepted {
            await self.turns.performSubmit(userText, attachments: attachments)
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

        case .none:
            break
        }
    }
}
