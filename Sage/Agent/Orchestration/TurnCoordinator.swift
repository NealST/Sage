//
//  TurnCoordinator.swift
//  Sage
//
//  Orchestrates thread + skill recall (Plan model) → plan →
//  (act confirm) → execute → review → persist judgment (Plan model).
//

import Foundation

/// Owns submit / retry and the three-sub-agent loop for a single session.
@MainActor
final class TurnCoordinator {
    private let state: AgentSessionState
    private let planProgress: PlanProgress
    private let taskStore: AgentTaskStore
    private let router: CompositeTaskRouter
    private let skillRecall: SkillRecallCoordinator
    private let modelGateway: AgentModelGateway
    private let settings: ModelSettings
    private let skillCatalog: () -> SkillCatalog?
    private let workspaceSnapshot: () -> TaskWorkspaceSnapshot
    private let streaming: StreamingTextPump
    private let topicCoordinator: TopicCoordinator
    private let skills: SkillSessionController
    let planner: PlanAgent
    let execute: ExecuteAgent
    let reviewer: ReviewAgent

    private weak var slashHost: SlashCommandHost?
    private var executeToolBatch: ((Bool) async -> Void)?
    private var handleStop: ((AgentPlan?) async -> Void)?
    /// User approved a side-effect work plan this turn.
    private(set) var planApproved = false
    private var reviewRounds = 0
    private var latestUserEventID: UUID?
    private var allowDriftOffer = true
    /// Scheduled runs keep WorkPlan on the task so the recipe can be frozen.
    private var keepWorkPlanAfterComplete = false
    var onTaskSettled: ((UUID, WorkPlan?, AgentTaskSettlement) async -> Void)?

    init(
        state: AgentSessionState,
        planProgress: PlanProgress,
        taskStore: AgentTaskStore,
        router: CompositeTaskRouter,
        skillRecall: SkillRecallCoordinator,
        modelGateway: AgentModelGateway,
        settings: ModelSettings,
        skillCatalog: @escaping () -> SkillCatalog?,
        workspaceSnapshot: @escaping () -> TaskWorkspaceSnapshot,
        streaming: StreamingTextPump,
        topicCoordinator: TopicCoordinator,
        skills: SkillSessionController
    ) {
        self.state = state
        self.planProgress = planProgress
        self.taskStore = taskStore
        self.router = router
        self.skillRecall = skillRecall
        self.modelGateway = modelGateway
        self.settings = settings
        self.skillCatalog = skillCatalog
        self.workspaceSnapshot = workspaceSnapshot
        self.streaming = streaming
        self.topicCoordinator = topicCoordinator
        self.skills = skills
        self.planner = PlanAgent(state: state, modelGateway: modelGateway)
        self.reviewer = ReviewAgent(state: state, modelGateway: modelGateway)
        self.execute = ExecuteAgent(
            state: state,
            planProgress: planProgress,
            taskStore: taskStore,
            modelGateway: modelGateway,
            streaming: streaming
        )
    }

    func bind(
        slashHost: SlashCommandHost,
        executeToolBatch: @escaping (Bool) async -> Void,
        handleStop: @escaping (AgentPlan?) async -> Void
    ) {
        self.slashHost = slashHost
        self.executeToolBatch = executeToolBatch
        self.handleStop = handleStop
        execute.bind(
            executeTools: { [weak self] in
                await self?.executeToolBatch?(false)
            },
            onCandidateReply: { [weak self] text in
                await self?.reviewAndFinish(text)
            },
            handleStop: handleStop
        )
    }

    /// Returns `true` once the user message was accepted into history (draft can clear).
    func performSubmit(_ userText: String) async -> Bool {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let slashHost {
            let enabledSkillNames = (skillCatalog()?.enabledSkills ?? []).map(\.name)
            if let handled = await SlashCommandRegistry.handle(
                trimmed,
                host: slashHost,
                enabledSkillNames: enabledSkillNames
            ) {
                return handled
            }
        }

        if state.activeTask?.pendingPlan != nil || state.hasPendingPlan {
            state.enterFailed(
                message: "Finish, cancel, or retry the pending plan before sending a new request."
            )
            return false
        }

        guard settings.isConfigured else {
            state.enterFailed(message: ModelClientError.notConfigured.localizedDescription)
            return false
        }

        state.clearCompletedPhase()
        state.clearFailedPhase()
        resetTurn()

        let snapshot = workspaceSnapshot()
        let route: TaskRoute
        let beganNewThread: Bool
        if state.forceFreshOnNextSubmit {
            state.forceFreshOnNextSubmit = false
            state.contextHint = nil
            state.clearTopicDriftOffer()
            guard await taskStore.beginNewTask(relatedTo: []) != nil else { return false }
            route = .continueActive(reason: "User forced a fresh task boundary")
            beganNewThread = true
        } else {
            let decided = await router.route(
                input: trimmed,
                workspace: snapshot
            )
            guard let applied = await taskStore.apply(decided) else { return false }
            route = applied
            beganNewThread = applied.action != .continueActive
        }

        guard await taskStore.ensureActiveTask() else { return false }

        if let plan = state.activeTask?.pendingPlan {
            planProgress.replace(plan)
            state.enterAwaitingConfirmation()
            return false
        }

        let userEvent = AgentEvent(
            kind: .userInput,
            content: trimmed,
            context: route.eventContext
        )
        guard await taskStore.commit(
            appendEvents: [userEvent],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .active
                task.pendingPlan = nil
                if task.summary == nil {
                    task.summary = String(trimmed.prefix(160))
                }
                for relatedID in route.relatedTaskIDs
                    where relatedID != task.id && !task.relatedTaskIDs.contains(relatedID) {
                    task.relatedTaskIDs.append(relatedID)
                }
            }
        ) else { return false }

        if let hint = route.userVisibleHint {
            state.contextHint = hint
        }

        latestUserEventID = userEvent.id
        allowDriftOffer = !beganNewThread

        state.enterThinking()
        state.lastAssistantText = nil
        streaming.clear()
        skillRecall.clearTurnCache()

        let readyForModel = await skillRecall.prepareSkillsForTurn(query: trimmed)
        guard readyForModel else { return true }

        await presentWorkPlan(for: trimmed, autoConfirm: false)
        return true
    }

    /// Timed recipe: skip routing. First-run `act` waits on the spawned task.
    func performScheduledRun(prompt: String, frozenPlan: WorkPlan?) async {
        resetTurn()
        keepWorkPlanAfterComplete = true
        allowDriftOffer = false
        state.skipsSessionToolGate = true
        defer {
            keepWorkPlanAfterComplete = false
            state.skipsSessionToolGate = false
        }

        let userEvent = AgentEvent(kind: .userInput, content: prompt, protected: true)
        guard await taskStore.commit(
            appendEvents: [userEvent],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .active
                task.pendingPlan = nil
                if task.summary == nil {
                    task.summary = String(prompt.prefix(160))
                }
                if let frozenPlan {
                    task.workPlan = frozenPlan
                }
            }
        ) else { return }

        latestUserEventID = userEvent.id
        state.enterThinking()
        state.lastAssistantText = nil
        streaming.clear()
        skillRecall.clearTurnCache()

        if let frozenPlan {
            planApproved = true
            await activateRecalledSkills(from: frozenPlan)
            await execute.start()
            return
        }

        _ = await skillRecall.prepareSkillsForTurn(query: prompt)
        await presentWorkPlan(for: prompt, autoConfirm: false)
    }

    /// Plan sub-agent. Confirm only when the strategy will change the Mac.
    private func presentWorkPlan(for userText: String, autoConfirm: Bool) async {
        do {
            try Task.checkCancellation()
            let catalogNames = (skillCatalog()?.enabledSkills ?? []).map(\.name)
            let workPlan = try await planner.propose(
                userText: userText,
                skillAppendix: skillRecall.cachedResult?.text ?? "",
                allowedSkillNames: catalogNames
            )
            try Task.checkCancellation()
            guard await taskStore.commit(
                appendEvents: [],
                deleteEventIDs: [],
                mutate: { task in
                    task.workPlan = workPlan
                    task.status = workPlan.requiresConfirmation ? .awaitingApproval : .active
                }
            ) else { return }

            applyThreadOffer(from: workPlan)

            if workPlan.requiresConfirmation, !autoConfirm {
                state.enterAwaitingConfirmation()
                return
            }
            planApproved = true
            await activateRecalledSkills(from: workPlan)
            await execute.start()
        } catch is CancellationError {
            streaming.clear()
            await handleStop?(nil)
        } catch {
            streaming.clear()
            await taskStore.markFailed(error.localizedDescription)
        }
    }

    func performRetry() async {
        if let plan = state.activeTask?.pendingPlan ?? planProgress.plan {
            planProgress.replace(plan)
            await executeToolBatch?(true)
            return
        }
        if state.activeTask?.workPlan?.requiresConfirmation == true, !planApproved {
            state.enterAwaitingConfirmation()
            return
        }

        guard settings.isConfigured else {
            state.enterFailed(message: ModelClientError.notConfigured.localizedDescription)
            return
        }
        guard !state.events.isEmpty else { return }

        await execute.start()
    }

    func runModelTurn() async {
        if state.activeTask?.workPlan == nil,
           let userText = state.events.last(where: { $0.kind == .userInput })?.content {
            await presentWorkPlan(for: userText, autoConfirm: false)
            return
        }
        await execute.start()
    }

    func handleTurn(_ turn: ModelTurn) async {
        await execute.handleTurn(turn)
    }

    var canOfferMoreTools: Bool {
        execute.canOfferMoreTools
    }

    func notePlanApproved() {
        planApproved = true
    }

    func extendAndContinueToolRounds() async {
        execute.extendToolBatchLimit()
        guard await persistClearedPendingPrompt() else { return }
        await execute.continueWithTools()
    }

    func finishWithoutMoreToolRounds() async {
        await execute.finishWithoutMoreTools()
    }

    func pauseForToolRoundLimit() async {
        await execute.pauseForToolRoundLimit()
    }

    @discardableResult
    private func persistClearedPendingPrompt() async -> Bool {
        guard state.pendingPrompt != nil || state.activeTask?.pendingPrompt != nil else {
            return true
        }
        return await taskStore.commit(
            appendEvents: [],
            deleteEventIDs: []
        ) { task in
                task.pendingPrompt = nil
        }
    }

    func startExecution() async {
        planApproved = true
        if let workPlan = state.activeTask?.workPlan {
            await activateRecalledSkills(from: workPlan)
        }
        await execute.start()
    }

    /// Review sub-agent. Accept finishes; revise sends execute around again.
    private func reviewAndFinish(_ draft: String) async {
        let workPlan = state.activeTask?.workPlan
        if workPlan?.kind == .answer {
            await finalizeAssistantText(draft, considerPersist: false)
            return
        }

        do {
            try Task.checkCancellation()
            if !draft.isEmpty {
                streaming.flush(draft)
            }
            let verdict = try await reviewer.evaluate()
            try Task.checkCancellation()

            if verdict.decision == .accept || reviewRounds >= ReviewAgent.maxRevisions {
                state.reviewFeedback = nil
                await finalizeAssistantText(draft, considerPersist: true)
                return
            }

            reviewRounds += 1
            state.reviewFeedback = verdict.feedback.nilIfEmpty
                ?? "The result does not fully match the plan. Finish the remaining work."
            execute.resetLoop()
            await execute.start()
        } catch is CancellationError {
            streaming.clear()
            await handleStop?(nil)
        } catch {
            // A reviewer failure should not hide a finished execute pass.
            state.reviewFeedback = nil
            await finalizeAssistantText(draft, considerPersist: true)
        }
    }

    func finalizeAssistantText(
        _ text: String,
        emptyFallback: String = "I couldn't produce a reply.",
        considerPersist: Bool = false
    ) async {
        let reply = text.isEmpty ? emptyFallback : text
        let alreadyConsidered = state.activeTask?.skillPersistConsidered == true
        let settledID = state.activeTaskID
        let settledPlan = state.activeTask?.workPlan
        guard await taskStore.commit(
            appendEvents: [AgentEvent(kind: .assistantResponse, content: reply)],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .completed
                task.pendingPlan = nil
                task.pendingPrompt = nil
                if !keepWorkPlanAfterComplete {
                    task.workPlan = nil
                }
                task.skillPersistConsidered = true
            }
        ) else { return }

        streaming.clear()
        state.reviewFeedback = nil
        state.clearPendingPrompt()
        state.lastAssistantText = reply
        state.enterCompleted(summary: reply)
        planProgress.clear()
        topicCoordinator.generateTopicIfNeeded(for: state.activeTask)

        if let settledID {
            await onTaskSettled?(settledID, settledPlan, .completed)
        }

        if considerPersist, !alreadyConsidered, !keepWorkPlanAfterComplete, let task = state.activeTask {
            skills.considerPersistenceAfterReview(for: task) { [planner] in
                await planner.judgePersistence(task: task)
            }
        }
    }

    private func applyThreadOffer(from workPlan: WorkPlan) {
        guard allowDriftOffer,
              workPlan.threadAdvice == .offerFresh,
              state.topicDriftOffer == nil,
              let task = state.activeTask,
              task.events.count >= TopicDriftDetector.minimumPriorEvents,
              state.suppressedDriftOfferTaskID != task.id,
              let userEventID = latestUserEventID
        else { return }

        let label = workPlan.threadLabel
            ?? TopicDriftDetector.threadLabel(
                topic: task.topic,
                abstract: task.abstract,
                summary: task.summary
            )
            ?? "this task"
        state.topicDriftOffer = TopicDriftOffer(
            taskID: task.id,
            triggeringUserEventID: userEventID,
            topicLabel: label
        )
        state.contextHint = nil
    }

    private func activateRecalledSkills(from workPlan: WorkPlan) async {
        guard !workPlan.skillNames.isEmpty else { return }
        await skillRecall.loadSkillsByName(workPlan.skillNames)
    }

    private func resetTurn() {
        execute.resetLoop()
        planApproved = false
        reviewRounds = 0
        state.reviewFeedback = nil
    }
}
