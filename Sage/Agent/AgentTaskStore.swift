//
//  AgentTaskStore.swift
//  Sage
//
//  Persistence and task-switch surface. Mutates AgentSessionState + PlanProgress directly.
//

import Foundation

@MainActor
final class AgentTaskStore {
    private let state: AgentSessionState
    private let planProgress: PlanProgress
    private let taskRepository: any TaskRepository
    private let skills: SkillSessionController
    private weak var topicCoordinator: TopicCoordinator?
    private weak var skillRecall: SkillRecallCoordinator?
    private weak var contextCompactor: ContextCompactor?
    /// Scheduled runner: persist the spawned task without moving last-active.
    private var suppressScopeActivePointer = false
    var onTaskFailed: ((UUID, String) async -> Void)?

    private var setsScopeActive: Bool { !suppressScopeActivePointer }

    static let maxRelatedTaskIDs = 8

    init(
        state: AgentSessionState,
        planProgress: PlanProgress,
        taskRepository: any TaskRepository,
        skills: SkillSessionController
    ) {
        self.state = state
        self.planProgress = planProgress
        self.taskRepository = taskRepository
        self.skills = skills
    }

    func bind(
        topicCoordinator: TopicCoordinator,
        skillRecall: SkillRecallCoordinator,
        contextCompactor: ContextCompactor? = nil
    ) {
        self.topicCoordinator = topicCoordinator
        self.skillRecall = skillRecall
        self.contextCompactor = contextCompactor
    }

    // MARK: - Commit / create

    /// Updates memory only after a successful atomic DB mutation.
    @discardableResult
    func commit(
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        mutate: (inout TaskRecord) -> Void = { _ in }
    ) async -> Bool {
        guard !state.isTornDown else { return false }
        guard var task = state.activeTask else { return false }
        mutate(&task)
        if !deleteEventIDs.isEmpty {
            let deleteSet = Set(deleteEventIDs)
            task.events.removeAll { deleteSet.contains($0.id) }
        }
        task.events.append(contentsOf: appendEvents)
        task.activatedSkillNames = state.activatedSkillNames
        task.updatedAt = .now
        do {
            try await taskRepository.mutateTask(
                task,
                appendEvents: appendEvents,
                deleteEventIDs: deleteEventIDs,
                setActive: setsScopeActive
            )
            adoptTaskInMemory(task)
            return true
        } catch {
            state.enterFailed(message: "Could not save task history: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func createAndActivateTask(relatedTo relatedTaskIDs: [UUID]) async -> UUID? {
        guard !state.isTornDown else { return nil }
        contextCompactor?.cancel()
        suppressScopeActivePointer = false
        let scopedRelated = await filterRelatedIDsToScope(relatedTaskIDs)
        let task = TaskRecord(
            projectID: state.focusedProject?.id,
            relatedTaskIDs: scopedRelated
        )
        do {
            try await taskRepository.saveTaskState(task, setActive: true)
            state.activeTask = task
            state.activeTaskID = task.id
            state.pendingPrompt = nil
            state.refreshSummary(for: task)
            state.enterIdle()
            state.lastAssistantText = nil
            planProgress.clear()
            return task.id
        } catch {
            state.enterFailed(message: "Could not create task storage: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func ensureActiveTask() async -> Bool {
        if state.activeTaskID != nil, state.activeTask != nil { return true }
        return await createAndActivateTask(relatedTo: []) != nil
    }

    @discardableResult
    func beginNewTask(relatedTo relatedTaskIDs: [UUID] = []) async -> UUID? {
        contextCompactor?.cancel()
        let inheritedRelated = relatedTaskIDs

        if var closing = state.activeTask {
            let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: closing.events)
            if !retractIDs.isEmpty {
                let deleteSet = Set(retractIDs)
                closing.events.removeAll { deleteSet.contains($0.id) }
            }

            do {
                if closing.events.isEmpty {
                    try await taskRepository.deleteTask(id: closing.id)
                    state.removeSummary(id: closing.id)
                } else {
                    if closing.status == .active || closing.status == .awaitingApproval {
                        closing.status = .completed
                    }
                    closing.pendingPlan = nil
                    closing.pendingPrompt = nil
                    closing.workPlan = nil
                    closing.workingMemory = closing.workingMemory?.validated(against: closing.events)
                    closing.updatedAt = .now
                    try await taskRepository.mutateTask(
                        closing,
                        appendEvents: [],
                        deleteEventIDs: retractIDs,
                        setActive: false
                    )
                    state.refreshSummary(for: closing)
                    topicCoordinator?.scheduleTopicGeneration(for: closing)
                    if !closing.skillPersistConsidered {
                        skills.scheduleExtraction(for: closing)
                    }
                }
                state.enterIdle()
                state.lastAssistantText = nil
                planProgress.clear()
            } catch {
                state.enterFailed(
                    message: "Could not close the previous task: \(error.localizedDescription)"
                )
                return nil
            }
        }

        state.activeTask = nil
        state.activeTaskID = nil
        state.clearTokenUsage()
        state.activatedSkillNames = []
        state.sessionAllowlist.reset()
        state.clearThreadRoutingNotices()
        skillRecall?.clearTurnCache()

        return await createAndActivateTask(
            relatedTo: Array(inheritedRelated.prefix(Self.maxRelatedTaskIDs))
        )
    }

    /// Creates a task for a schedule runner without closing or activating the window thread.
    /// `originScheduleID` is persisted so Recents can label the row as scheduled.
    @discardableResult
    func spawnScheduledTask(projectID: UUID?, summary: String?, originScheduleID: UUID?) async -> UUID? {
        guard !state.isTornDown else { return nil }
        contextCompactor?.cancel()
        suppressScopeActivePointer = true
        let task = TaskRecord(
            projectID: projectID,
            summary: summary,
            skillPersistConsidered: true,
            originScheduleID: originScheduleID
        )
        do {
            try await taskRepository.saveTaskState(task, setActive: false)
            state.activeTask = task
            state.activeTaskID = task.id
            state.enterIdle()
            state.lastAssistantText = nil
            planProgress.clear()
            state.clearTokenUsage()
            state.activatedSkillNames = []
            state.sessionAllowlist.reset()
            skillRecall?.clearTurnCache()
            return task.id
        } catch {
            state.enterFailed(message: "Could not create scheduled task: \(error.localizedDescription)")
            return nil
        }
    }

    func activateTask(_ id: UUID) async {
        guard id != state.activeTaskID else { return }
        contextCompactor?.cancel()
        suppressScopeActivePointer = false

        if var current = state.activeTask {
            if case .awaitingConfirmation = state.phase {
                if let plan = planProgress.plan ?? current.pendingPlan {
                    current.pendingPlan = plan
                }
                current.status = .awaitingApproval
            }
            current.pendingPrompt = state.pendingPrompt
            current.updatedAt = .now
            do {
                try await taskRepository.saveTaskState(current, setActive: false)
            } catch {
                state.enterFailed(
                    message: "Could not save task context: \(error.localizedDescription)"
                )
                return
            }
        }

        do {
            guard let task = try await taskRepository.loadTask(id: id) else {
                state.enterFailed(message: "Could not find that task context.")
                return
            }
            guard task.projectID == state.focusedProject?.id else {
                state.enterFailed(message: "That task belongs to a different project.")
                return
            }
            try await taskRepository.rememberScopeActiveTask(
                projectID: state.focusedProject?.id,
                taskID: id
            )
            state.activeTask = task
            state.activeTaskID = task.id
            state.refreshSummary(for: task)
            state.sessionAllowlist.reset()
            await restorePhaseFromActiveTask()
            state.clearTopicDriftOffer()
            state.suppressedDriftOfferTaskID = nil
            state.forceFreshOnNextSubmit = false
            state.contextHint = nil
        } catch {
            state.enterFailed(
                message: "Could not restore task context: \(error.localizedDescription)"
            )
        }
    }

    struct SplitOffTurnResult: Equatable {
        var newTaskID: UUID
        var needsModelTurn: Bool
        var userQuery: String
    }

    /// Peels the forked user message onto a new task. Replies after that line are dropped.
    func splitOffTurn(from userEventID: UUID) async -> SplitOffTurnResult? {
        guard !state.isTornDown else { return nil }
        guard var closing = state.activeTask else { return nil }
        contextCompactor?.cancel()
        guard let fork = AgentEventHelpers.forkLastUserInput(
            events: closing.events,
            userEventID: userEventID
        ) else { return nil }

        let oldID = closing.id
        let userQuery = fork.moved.content
        let userEvent = fork.moved

        closing.events = fork.kept
        closing.pendingPlan = nil
        closing.pendingPrompt = nil
        closing.workPlan = nil
        closing.workingMemory = closing.workingMemory?.validated(against: fork.kept)
        closing.updatedAt = .now
        if !closing.events.isEmpty,
           closing.status == .active || closing.status == .awaitingApproval {
            closing.status = .completed
        }

        let opening = TaskRecord(
            projectID: closing.projectID ?? state.focusedProject?.id,
            summary: userQuery.isEmpty ? nil : String(userQuery.prefix(160)),
            events: [userEvent],
            workingMemory: nil,
            pendingPlan: nil,
            relatedTaskIDs: [],
            activatedSkillNames: []
        )

        do {
            try await taskRepository.splitOffTurn(
                closingTask: closing,
                openingTask: opening,
                movedEventIDs: [userEvent.id]
            )
        } catch {
            state.enterFailed(
                message: "Could not start a new task: \(error.localizedDescription)"
            )
            return nil
        }

        if closing.events.isEmpty {
            state.removeSummary(id: oldID)
        } else {
            state.refreshSummary(for: closing)
            topicCoordinator?.scheduleTopicGeneration(for: closing)
            if !closing.skillPersistConsidered {
                skills.scheduleExtraction(for: closing)
            }
        }

        state.activeTask = opening
        state.activeTaskID = opening.id
        state.refreshSummary(for: opening)
        state.clearTokenUsage()
        state.activatedSkillNames = []
        state.lastAssistantText = nil
        skillRecall?.clearTurnCache()
        planProgress.clear()
        state.sessionAllowlist.reset()
        state.clearThreadRoutingNotices()
        await restorePhaseFromActiveTask()
        topicCoordinator?.scheduleTopicGeneration(for: opening)

        return SplitOffTurnResult(
            newTaskID: opening.id,
            needsModelTurn: true,
            userQuery: userQuery
        )
    }

    /// Applies a routing decision. Returns the effective route, or nil on hard failure.
    func apply(_ route: TaskRoute) async -> TaskRoute? {
        switch route.action {
        case .continueActive:
            return route

        case .beginNew:
            state.clearTopicDriftOffer()
            state.contextHint = nil
            guard await beginNewTask(relatedTo: route.relatedTaskIDs) != nil else {
                return nil
            }
            return route
        }
    }

    func restorePhaseFromActiveTask() async {
        guard let task = state.activeTask else {
            state.enterIdle()
            state.lastAssistantText = nil
            planProgress.clear()
            return
        }

        state.activatedSkillNames = task.activatedSkillNames
        state.pendingPrompt = task.pendingPrompt
        state.lastAssistantText = task.events.last {
            $0.kind == .assistantResponse && ($0.toolCalls?.isEmpty ?? true)
        }?.content

        if case .toolRoundLimit = task.pendingPrompt {
            if var plan = task.pendingPlan {
                normalizeRestoredPlan(&plan, events: task.events)
                if plan.steps.contains(where: { $0.status != .succeeded && $0.status != .skipped }) {
                    var updated = task
                    updated.pendingPlan = plan
                    state.activeTask = updated
                    planProgress.replace(plan)
                } else {
                    planProgress.clear()
                }
            } else {
                planProgress.clear()
            }
            state.enterAwaitingConfirmation()
            return
        }

        if case .toolApproval = task.pendingPrompt {
            if var plan = task.pendingPlan {
                normalizeRestoredPlan(&plan, events: task.events)
                var updated = task
                updated.pendingPlan = plan
                state.activeTask = updated
                planProgress.replace(plan)
                state.enterAwaitingConfirmation()
                return
            }
            state.clearPendingPrompt()
        }

        guard var plan = task.pendingPlan else {
            if task.workPlan?.requiresConfirmation == true,
               task.status == .awaitingApproval {
                state.enterAwaitingConfirmation()
                planProgress.clear()
                return
            }
            state.enterIdle()
            planProgress.clear()
            return
        }

        normalizeRestoredPlan(&plan, events: task.events)

        var updated = task
        let unfinished = plan.steps.contains {
            $0.status != .succeeded && $0.status != .skipped
        }
        if unfinished {
            updated.pendingPlan = plan
            state.activeTask = updated
            planProgress.replace(plan)
            state.enterAwaitingConfirmation()
        } else {
            updated.pendingPlan = nil
            state.activeTask = updated
            planProgress.clear()
            try? await taskRepository.saveTaskState(updated, setActive: setsScopeActive)
            state.refreshSummary(for: updated)
            if updated.events.last?.kind == .toolResult {
                state.enterFailed(
                    message: "Interrupted after tools finished. Retry to summarize."
                )
            } else {
                state.enterIdle()
            }
        }
    }

    private func normalizeRestoredPlan(_ plan: inout AgentPlan, events: [AgentEvent]) {
        for index in plan.steps.indices {
            if let result = events.last(where: {
                $0.kind == .toolResult && $0.toolCallID == plan.steps[index].toolCallID
            }) {
                if result.content.hasPrefix("ERROR:") {
                    plan.steps[index].status = .failed
                } else {
                    plan.steps[index].status = .succeeded
                }
            } else if plan.steps[index].status == .running {
                plan.steps[index].status = .pending
            }
        }
    }

    /// Writes `task` into memory, preserving a topic that arrived concurrently.
    func adoptTaskInMemory(_ task: TaskRecord) {
        var merged = task
        if merged.topic == nil,
           let current = state.activeTask,
           current.id == merged.id,
           let topic = current.topic {
            merged.topic = topic
            merged.abstract = current.abstract
            merged.topicUpdatedAt = current.topicUpdatedAt
        }
        if merged.workingMemory == nil,
           let current = state.activeTask,
           current.id == merged.id {
            merged.workingMemory = current.workingMemory
        }
        state.activeTask = merged
        state.pendingPrompt = merged.pendingPrompt
        state.refreshSummary(for: merged)
        if let plan = merged.pendingPlan {
            planProgress.replace(plan)
        } else {
            planProgress.clear()
        }
    }

    /// Writes working memory without replacing events or the plan.
    @discardableResult
    func applyWorkingMemory(_ memory: TaskWorkingMemory, to taskID: UUID) async -> Bool {
        guard memory.hasContent else { return false }
        guard state.activeTaskID == taskID else { return false }
        do {
            try await taskRepository.updateWorkingMemory(taskID: taskID, memory: memory)
        } catch {
            return false
        }
        guard state.activeTaskID == taskID else { return false }
        state.activeTask?.workingMemory = memory
        return true
    }

    /// Persist a single step status/result and keep in-memory plan in sync.
    @discardableResult
    func persistPlanStepStatus(_ step: AgentStep, in plan: AgentPlan) async -> Bool {
        guard var task = state.activeTask,
              task.id == (state.activeTaskID ?? task.id)
        else { return false }
        do {
            try await taskRepository.updatePlanStep(
                taskID: task.id,
                stepID: step.id,
                status: step.status,
                result: step.result
            )
            task.pendingPlan = plan
            task.status = .active
            task.updatedAt = .now
            adoptTaskInMemory(task)
            planProgress.update(plan)
            return true
        } catch {
            return false
        }
    }

    func failDuringExecution(plan: AgentPlan, message: String) async {
        state.retryState = nil
        planProgress.update(plan)
        guard var task = state.activeTask else {
            state.enterFailed(message: message)
            return
        }
        task.pendingPlan = plan
        task.status = .awaitingApproval
        task.updatedAt = .now
        do {
            try await taskRepository.saveTaskState(task, setActive: setsScopeActive)
            state.activeTask = task
            state.pendingPrompt = task.pendingPrompt
            state.refreshSummary(for: task)
            state.enterFailed(message: message)
        } catch {
            state.activeTask = task
            state.pendingPrompt = task.pendingPrompt
            state.enterFailed(
                message: "Could not save progress. \(error.localizedDescription)"
            )
        }
        await onTaskFailed?(task.id, message)
    }

    func markFailed(_ message: String) async {
        state.retryState = nil
        state.enterFailed(message: message)
        guard var task = state.activeTask else { return }
        task.status = .failed
        task.updatedAt = .now
        do {
            try await taskRepository.saveTaskState(task, setActive: setsScopeActive)
            state.activeTask = task
            state.refreshSummary(for: task)
        } catch {
            state.activeTask = task
        }
        await onTaskFailed?(task.id, message)
    }

    // MARK: - Helpers

    func filterRelatedIDsToScope(_ ids: [UUID]) async -> [UUID] {
        guard !ids.isEmpty else { return [] }
        let scope = state.focusedProject?.id
        if let filtered = try? await taskRepository.filterTaskIDs(ids, projectID: scope) {
            return Array(filtered.prefix(Self.maxRelatedTaskIDs))
        }
        // Fallback if the batch API fails — metadata only (no event/plan hydrate).
        var result: [UUID] = []
        for id in ids {
            guard let task = try? await taskRepository.loadTaskMetadata(id: id) else { continue }
            guard task.projectID == scope else { continue }
            if !result.contains(id) { result.append(id) }
        }
        return Array(result.prefix(Self.maxRelatedTaskIDs))
    }

    /// Sets recall TaskLocals for the active task around a tool dispatch.
    func withActiveTaskContext<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let applyTodos: @Sendable ([AgentTodoItem]) async -> Void = { [weak self] items in
            await self?.applyTodoList(items)
        }
        let applyMCPServers: @Sendable (Set<String>) async -> Void = { [weak self] names in
            await self?.applyUnlockedMCPServers(names)
        }
        return try await ActiveTaskContext.$repository.withValue(taskRepository) {
            try await ActiveTaskContext.$taskID.withValue(state.activeTaskID) {
                try await ActiveTaskContext.$applyTodoList.withValue(applyTodos) {
                    try await ActiveTaskContext.$unlockedMCPServerNames.withValue(
                        state.activeTask?.unlockedMCPServerNames ?? []
                    ) {
                        try await ActiveTaskContext.$applyUnlockedMCPServers.withValue(
                            applyMCPServers
                        ) {
                            try await operation()
                        }
                    }
                }
            }
        }
    }

    func applyTodoList(_ items: [AgentTodoItem]) {
        guard var task = state.activeTask else { return }
        task.todos = items
        state.activeTask = task
    }

    func applyUnlockedMCPServers(_ names: Set<String>) {
        guard var task = state.activeTask else { return }
        task.unlockedMCPServerNames = names
        state.activeTask = task
    }
}
