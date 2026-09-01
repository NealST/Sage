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
    let state: AgentSessionState
    let planProgress: PlanProgress
    let taskStore: AgentTaskStore
    let router: CompositeTaskRouter
    let skillRecall: SkillRecallCoordinator
    let modelGateway: AgentModelGateway
    let settings: ModelSettings
    let skillCatalog: () -> SkillCatalog?
    let workspaceSnapshot: () -> TaskWorkspaceSnapshot
    let streaming: StreamingTextPump
    let topicCoordinator: TopicCoordinator
    let skills: SkillSessionController
    let planner: PlanAgent
    let execute: ExecuteAgent
    let reviewer: ReviewAgent

    weak var slashHost: SlashCommandHost?
    var executeToolBatch: ((Bool) async -> Void)?
    var handleStop: ((AgentPlan?) async -> Void)?
    /// User approved a side-effect work plan this turn. Scoped to `turnLoopTaskID`.
    var planApproved = false
    var reviewRounds = 0
    var latestUserEventID: UUID?
    /// In-memory loop flags keyed by task, so switching threads does not leak them.
    var turnLoopByTask: [UUID: TurnLoopState] = [:]
    var turnLoopTaskID: UUID?

    struct TurnLoopState: Equatable {
        var planApproved = false
        var reviewRounds = 0
    }
    var allowDriftOffer = true
    /// Scheduled runs keep WorkPlan on the task so the recipe can be frozen.
    var keepWorkPlanAfterComplete = false
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
    func performSubmit(
        _ userText: String,
        attachments: [MessageAttachment] = []
    ) async -> Bool {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return false }
        guard attachments.allSatisfy(\.isAvailable) else {
            state.enterFailed(
                message: "One or more attachments are missing or unreadable. Remove them and try again."
            )
            return false
        }
        guard await replaceUnconfirmedPlanIfNeeded() else { return false }
        if attachments.isEmpty,
           !trimmed.isEmpty,
           let handled = await handleSlashIfNeeded(trimmed) {
            return handled
        }
        guard canAcceptNewUserTurn() else { return false }

        let query = MessageAttachment.submitQuery(text: trimmed, attachments: attachments)
        state.clearCompletedPhase()
        state.clearFailedPhase()
        resetTurn()

        guard let routing = await routeSubmittedTurn(query) else { return false }
        guard await taskStore.ensureActiveTask() else { return false }
        if let plan = state.activeTask?.pendingPlan {
            planProgress.replace(plan)
            state.enterAwaitingConfirmation()
            return false
        }
        guard await persistSubmittedUserEvent(
            trimmed,
            attachments: attachments,
            route: routing.route,
            summary: query
        ) else { return false }
        allowDriftOffer = !routing.beganNewThread
        state.enterThinking()
        state.lastAssistantText = nil
        streaming.clear()
        skillRecall.clearTurnCache()

        let readyForModel = skillRecall.prepareSkillsForTurn(query: query)
        guard readyForModel else { return true }
        await presentWorkPlan(for: query)
        return true
    }

    func handleSlashIfNeeded(_ trimmed: String) async -> Bool? {
        guard let slashHost else { return nil }
        let enabledSkillNames = (skillCatalog()?.enabledSkills ?? []).map(\.name)
        return await SlashCommandRegistry.handle(
            trimmed,
            host: slashHost,
            enabledSkillNames: enabledSkillNames
        )
    }

    func canAcceptNewUserTurn() -> Bool {
        guard settings.isConfigured else {
            state.enterFailed(message: ModelClientError.notConfigured.localizedDescription)
            return false
        }
        return true
    }
}

extension TurnCoordinator {
    /// Freeze the card for a frame, then drop it so the new submit can plan.
    func replaceUnconfirmedPlanIfNeeded() async -> Bool {
        guard case .awaitingConfirmation = state.phase else { return true }
        if state.shouldDisableConfirmationActions {
            await Self.yieldForNextRunLoop()
        }
        guard await discardUnconfirmedTurn() else {
            state.unfreezeConfirmationActions()
            return false
        }
        return true
    }

    /// Drop an unconfirmed card so a new composer submit can replace it.
    /// Leaves phase unchanged; the caller moves to thinking after persisting the new turn.
    func discardUnconfirmedTurn() async -> Bool {
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: state.events)
        guard await taskStore.commit(
            appendEvents: [],
            deleteEventIDs: retractIDs,
            mutate: { task in
                task.pendingPlan = nil
                task.pendingPrompt = nil
                task.workPlan = nil
                task.status = .active
            }
        ) else { return false }
        state.clearPendingPrompt()
        planProgress.clear()
        return true
    }

    private static func yieldForNextRunLoop() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    struct SubmitRouting {
        var route: TaskRoute
        var beganNewThread: Bool
    }

    func routeSubmittedTurn(_ trimmed: String) async -> SubmitRouting? {
        let snapshot = workspaceSnapshot()
        let route: TaskRoute
        let beganNewThread: Bool
        if state.forceFreshOnNextSubmit {
            state.forceFreshOnNextSubmit = false
            state.contextHint = nil
            state.clearTopicDriftOffer()
            guard await taskStore.beginNewTask(relatedTo: []) != nil else { return nil }
            route = .continueActive(reason: "User forced a fresh task boundary")
            beganNewThread = true
        } else {
            let decided = router.route(input: trimmed, workspace: snapshot)
            guard let applied = await taskStore.apply(decided) else { return nil }
            route = applied
            beganNewThread = applied.action != .continueActive
        }
        return SubmitRouting(route: route, beganNewThread: beganNewThread)
    }

    func persistSubmittedUserEvent(
        _ trimmed: String,
        attachments: [MessageAttachment] = [],
        route: TaskRoute,
        summary: String? = nil
    ) async -> Bool {
        let userEvent = AgentEvent(
            kind: .userInput,
            content: trimmed,
            context: route.eventContext,
            attachments: attachments
        )
        let summaryText = summary ?? trimmed
        guard await taskStore.commit(
            appendEvents: [userEvent],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .active
                task.pendingPlan = nil
                if task.summary == nil {
                    task.summary = String(summaryText.prefix(160))
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
        return true
    }

    /// Timed recipe: skip routing. First-run `act` waits on the spawned task.
    func performScheduledRun(prompt: String, frozenPlan: WorkPlan?) async {
        resetTurn()
        keepWorkPlanAfterComplete = true
        allowDriftOffer = false
        defer {
            keepWorkPlanAfterComplete = false
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

        _ = skillRecall.prepareSkillsForTurn(query: prompt)
        await presentWorkPlan(for: prompt)
    }
}
