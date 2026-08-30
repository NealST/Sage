//
//  AgentTaskStore.swift
//  Sage
//
//  Persistence and task-switch surface. Mutates AgentSessionState + PlanProgress directly.
//

import Foundation

@MainActor
final class AgentTaskStore {
    let state: AgentSessionState
    let planProgress: PlanProgress
    let taskRepository: any TaskRepository
    let skills: SkillSessionController
    weak var topicCoordinator: TopicCoordinator?
    weak var skillRecall: SkillRecallCoordinator?
    weak var contextCompactor: ContextCompactor?
    /// Scheduled runner: persist the spawned task without moving last-active.
    var suppressScopeActivePointer = false
    var onTaskFailed: ((UUID, String) async -> Void)?
    /// Fired after this window’s active task identity changes.
    var onActiveTaskChanged: (() -> Void)?
    /// Fired when the previous thread is archived or deleted.
    var onTaskClosed: ((UUID) -> Void)?

    var setsScopeActive: Bool { !suppressScopeActivePointer }

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
        let deletedAttachments: [MessageAttachment]
        if !deleteEventIDs.isEmpty {
            let deleteSet = Set(deleteEventIDs)
            deletedAttachments = task.events
                .filter { deleteSet.contains($0.id) }
                .flatMap(\.attachments)
            task.events.removeAll { deleteSet.contains($0.id) }
        } else {
            deletedAttachments = []
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
            try? await taskRepository.pruneManagedAttachmentCopies(deletedAttachments)
            return true
        } catch {
            state.enterFailed(message: "Could not save task history: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func clearPendingPrompt() async -> Bool {
        guard state.pendingPrompt != nil || state.activeTask?.pendingPrompt != nil else {
            return true
        }
        return await commit(appendEvents: [], deleteEventIDs: []) { task in
            task.pendingPrompt = nil
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
            onActiveTaskChanged?()
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
        if let closing = state.activeTask {
            let closed = await closeActiveTask(closing)
            if !closed { return nil }
        }
        state.activeTask = nil
        state.activeTaskID = nil
        state.clearTokenUsage()
        state.activatedSkillNames = []
        state.sessionAllowlist.reset()
        state.clearThreadRoutingNotices()
        skillRecall?.clearTurnCache()

        return await createAndActivateTask(
            relatedTo: Array(relatedTaskIDs.prefix(Self.maxRelatedTaskIDs))
        )
    }

    func closeActiveTask(_ closing: TaskRecord) async -> Bool {
        var closing = closing
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: closing.events)
        if !retractIDs.isEmpty {
            let deleteSet = Set(retractIDs)
            closing.events.removeAll { deleteSet.contains($0.id) }
        }
        do {
            if closing.events.isEmpty {
                try await taskRepository.deleteTask(id: closing.id)
                ToolAuthorizationGrantStore.shared.removeTaskGrants(
                    scopeID: "task:\(closing.id.uuidString)"
                )
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
            onTaskClosed?(closing.id)
            return true
        } catch {
            state.enterFailed(
                message: "Could not close the previous task: \(error.localizedDescription)"
            )
            return false
        }
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
            onActiveTaskChanged?()
            return task.id
        } catch {
            state.enterFailed(message: "Could not create scheduled task: \(error.localizedDescription)")
            return nil
        }
    }
}
