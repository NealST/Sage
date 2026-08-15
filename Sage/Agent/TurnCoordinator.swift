//
//  TurnCoordinator.swift
//  Sage
//

import Foundation

/// Owns submit / retry / model-turn orchestration for a single agent session.
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

    private weak var slashHost: SlashCommandHost?
    private var confirmPlan: (() async -> Void)?
    private var handleStop: ((AgentPlan?) async -> Void)?

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
        topicCoordinator: TopicCoordinator
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
    }

    func bind(
        slashHost: SlashCommandHost,
        confirmPlan: @escaping () async -> Void,
        handleStop: @escaping (AgentPlan?) async -> Void
    ) {
        self.slashHost = slashHost
        self.confirmPlan = confirmPlan
        self.handleStop = handleStop
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

        guard settings.isConfigured else {
            state.phase = .failed(message: ModelClientError.notConfigured.localizedDescription)
            return false
        }

        if state.activeTask?.pendingPlan != nil || state.hasPendingPlan {
            state.phase = .failed(
                message: "Finish, cancel, or retry the pending plan before sending a new request."
            )
            return false
        }

        if case .completed = state.phase { state.phase = .idle }
        if case .failed = state.phase { state.phase = .idle }

        let route: TaskRoute
        if state.forceFreshOnNextSubmit {
            state.forceFreshOnNextSubmit = false
            state.contextHint = nil
            guard await taskStore.beginNewTask(relatedTo: []) != nil else { return false }
            route = .continueActive(reason: "User forced a fresh task boundary")
        } else {
            let decided = await router.route(
                input: trimmed,
                workspace: workspaceSnapshot()
            )
            guard let applied = await taskStore.apply(decided) else { return false }
            route = applied
        }

        guard await taskStore.ensureActiveTask() else { return false }

        if let plan = state.activeTask?.pendingPlan {
            planProgress.replace(plan)
            state.phase = .awaitingConfirmation
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

        state.phase = .thinking
        state.lastAssistantText = nil
        streaming.clear()
        skillRecall.clearTurnCache()

        let readyForModel = await skillRecall.prepareSkillsForTurn(query: trimmed)
        guard readyForModel else { return true }

        await runModelTurn()
        return true
    }

    func performRetry() async {
        if let plan = state.activeTask?.pendingPlan ?? planProgress.plan {
            planProgress.replace(plan)
            state.phase = .awaitingConfirmation
            await confirmPlan?()
            return
        }

        guard settings.isConfigured else {
            state.phase = .failed(message: ModelClientError.notConfigured.localizedDescription)
            return
        }
        guard !state.events.isEmpty else { return }

        let resumeWithoutTools = state.events.last?.kind == .toolResult
        await runModelTurn(includeTools: !resumeWithoutTools)
    }

    func runModelTurn(includeTools: Bool = true) async {
        state.phase = .thinking
        streaming.clear()
        if includeTools {
            skillRecall.clearTurnCache()
        }
        do {
            try Task.checkCancellation()
            let turn = try await modelGateway.streamComplete(includeTools: includeTools)
            try Task.checkCancellation()
            await handleTurn(turn)
        } catch is CancellationError {
            streaming.clear()
            await handleStop?(nil)
        } catch {
            streaming.clear()
            await taskStore.markFailed(error.localizedDescription)
        }
    }

    func handleTurn(_ turn: ModelTurn) async {
        if !turn.toolCalls.isEmpty {
            let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "I can do this in \(turn.toolCalls.count) step\(turn.toolCalls.count == 1 ? "" : "s")."

            let storedCalls = turn.toolCalls.map {
                ToolCallRecord(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON)
            }
            let plan = PlanExecutor.makePlan(
                from: turn.toolCalls,
                summary: summary,
                pathGuardPolicy: state.pathGuardPolicy
            )
            guard await taskStore.commit(
                appendEvents: [
                    AgentEvent(
                        kind: .assistantResponse,
                        content: summary,
                        toolCalls: storedCalls
                    ),
                ],
                deleteEventIDs: [],
                mutate: { task in
                    task.pendingPlan = plan
                    task.status = .awaitingApproval
                }
            ) else { return }

            streaming.clear()
            planProgress.replace(plan)
            state.phase = .awaitingConfirmation
            return
        }

        await finalizeAssistantText(
            turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    /// Shared completion path for text-only turns and post-tool summaries.
    func finalizeAssistantText(
        _ text: String,
        emptyFallback: String = "I couldn't produce a reply."
    ) async {
        let reply = text.isEmpty ? emptyFallback : text
        guard await taskStore.commit(
            appendEvents: [AgentEvent(kind: .assistantResponse, content: reply)],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .completed
            }
        ) else { return }

        streaming.clear()
        state.lastAssistantText = reply
        state.phase = .completed(summary: reply)
        planProgress.clear()
        topicCoordinator.generateTopicIfNeeded(for: state.activeTask)
    }
}
