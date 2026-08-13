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

    func bind(topicCoordinator: TopicCoordinator, skillRecall: SkillRecallCoordinator) {
        self.topicCoordinator = topicCoordinator
        self.skillRecall = skillRecall
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
                setActive: true
            )
            adoptTaskInMemory(task)
            return true
        } catch {
            state.phase = .failed(message: "Could not save task history: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func createAndActivateTask(relatedTo relatedTaskIDs: [UUID]) async -> UUID? {
        guard !state.isTornDown else { return nil }
        let scopedRelated = await filterRelatedIDsToScope(relatedTaskIDs)
        let task = TaskRecord(
            projectID: state.focusedProject?.id,
            relatedTaskIDs: scopedRelated
        )
        do {
            try await taskRepository.saveTaskState(task, setActive: true)
            state.activeTask = task
            state.activeTaskID = task.id
            state.refreshSummary(for: task)
            state.phase = .idle
            state.lastAssistantText = nil
            planProgress.clear()
            return task.id
        } catch {
            state.phase = .failed(message: "Could not create task storage: \(error.localizedDescription)")
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
        var inheritedRelated = relatedTaskIDs

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
                    closing.updatedAt = .now
                    try await taskRepository.mutateTask(
                        closing,
                        appendEvents: [],
                        deleteEventIDs: retractIDs,
                        setActive: false
                    )
                    state.refreshSummary(for: closing)
                    topicCoordinator?.scheduleTopicGeneration(for: closing)
                    skills.scheduleExtraction(for: closing)
                    if !inheritedRelated.contains(closing.id) {
                        inheritedRelated.insert(closing.id, at: 0)
                    }
                }
                state.phase = .idle
                state.lastAssistantText = nil
                planProgress.clear()
            } catch {
                state.phase = .failed(
                    message: "Could not close the previous task: \(error.localizedDescription)"
                )
                return nil
            }
        }

        state.activeTask = nil
        state.activeTaskID = nil
        state.clearTokenUsage()
        state.activatedSkillNames = []
        skillRecall?.clearTurnCache()

        return await createAndActivateTask(
            relatedTo: Array(inheritedRelated.prefix(Self.maxRelatedTaskIDs))
        )
    }

    func activateTask(_ id: UUID) async {
        guard id != state.activeTaskID else { return }

        if var current = state.activeTask {
            if case .awaitingConfirmation = state.phase, let plan = planProgress.plan ?? current.pendingPlan {
                current.pendingPlan = plan
                current.status = .awaitingApproval
            }
            current.updatedAt = .now
            do {
                try await taskRepository.saveTaskState(current, setActive: false)
            } catch {
                state.phase = .failed(
                    message: "Could not save task context: \(error.localizedDescription)"
                )
                return
            }
        }

        do {
            guard let task = try await taskRepository.loadTask(id: id) else {
                state.phase = .failed(message: "Could not find that task context.")
                return
            }
            guard task.projectID == state.focusedProject?.id else {
                state.phase = .failed(message: "That task belongs to a different project.")
                return
            }
            try await taskRepository.rememberScopeActiveTask(
                projectID: state.focusedProject?.id,
                taskID: id
            )
            state.activeTask = task
            state.activeTaskID = task.id
            state.refreshSummary(for: task)
            await restorePhaseFromActiveTask()
            state.contextHint = ContextHint.forTask(task)
        } catch {
            state.phase = .failed(
                message: "Could not restore task context: \(error.localizedDescription)"
            )
        }
    }

    /// Shared resume path for heuristic + local-model routing.
    func resumeTask(
        _ id: UUID,
        extraRelatedIDs: [UUID],
        inputForTopicUpdate: String?,
        confidence: Double,
        reason: String,
        userVisibleHint: String?
    ) async -> TaskRoute? {
        if await taskHasPendingPlan(id) {
            return .continueActive(
                confidence: confidence,
                reason: "Resume skipped: target has pending plan"
            )
        }

        let previousID = state.activeTaskID
        await activateTask(id)
        guard state.activeTaskID == id else { return nil }

        if var task = state.activeTask {
            var changed = false
            if let previousID,
               previousID != task.id,
               !task.relatedTaskIDs.contains(previousID) {
                task.relatedTaskIDs.insert(previousID, at: 0)
                changed = true
            }
            for relatedID in extraRelatedIDs
                where relatedID != task.id && !task.relatedTaskIDs.contains(relatedID) {
                task.relatedTaskIDs.append(relatedID)
                changed = true
            }
            if task.relatedTaskIDs.count > Self.maxRelatedTaskIDs {
                task.relatedTaskIDs = Array(task.relatedTaskIDs.prefix(Self.maxRelatedTaskIDs))
                changed = true
            }
            if changed {
                task.updatedAt = .now
                do {
                    try await taskRepository.saveTaskState(task, setActive: true)
                    adoptTaskInMemory(task)
                } catch {
                    state.phase = .failed(
                        message: "Could not update related context: \(error.localizedDescription)"
                    )
                    return nil
                }
            }

            if let inputForTopicUpdate,
               let existingTopic = task.topic,
               let existingAbstract = task.abstract {
                topicCoordinator?.scheduleTopicRefreshOnResume(
                    taskID: id,
                    existingTopic: existingTopic,
                    existingAbstract: existingAbstract,
                    newInput: inputForTopicUpdate
                )
            }
        }

        let hint = userVisibleHint ?? state.activeTask.map(ContextHint.forTask)
        if let hint { state.contextHint = hint }
        return .resume(
            id,
            confidence: confidence,
            reason: reason,
            userVisibleHint: hint
        )
    }

    /// Applies a routing decision. Returns the effective route, or nil on hard failure.
    func apply(_ route: TaskRoute) async -> TaskRoute? {
        switch route.action {
        case .continueActive:
            return route
        case .beginNew:
            state.contextHint = nil
            guard await beginNewTask(relatedTo: route.relatedTaskIDs) != nil else {
                return nil
            }
            return route
        case .resumeTask(let id):
            return await resumeTask(
                id,
                extraRelatedIDs: route.relatedTaskIDs,
                inputForTopicUpdate: nil,
                confidence: route.confidence,
                reason: route.reason,
                userVisibleHint: route.userVisibleHint
            )
        }
    }

    func restorePhaseFromActiveTask() async {
        guard let task = state.activeTask else {
            state.phase = .idle
            state.lastAssistantText = nil
            planProgress.clear()
            return
        }

        state.activatedSkillNames = task.activatedSkillNames
        state.lastAssistantText = task.events.last(where: {
            $0.kind == .assistantResponse && ($0.toolCalls?.isEmpty ?? true)
        })?.content

        guard var plan = task.pendingPlan else {
            state.phase = .idle
            planProgress.clear()
            return
        }

        for index in plan.steps.indices {
            if let result = task.events.last(where: {
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

        var updated = task
        let unfinished = plan.steps.contains {
            $0.status != .succeeded && $0.status != .skipped
        }
        if unfinished {
            updated.pendingPlan = plan
            state.activeTask = updated
            planProgress.replace(plan)
            state.phase = .awaitingConfirmation
        } else {
            updated.pendingPlan = nil
            state.activeTask = updated
            planProgress.clear()
            try? await taskRepository.saveTaskState(updated, setActive: true)
            state.refreshSummary(for: updated)
            if updated.events.last?.kind == .toolResult {
                state.phase = .failed(
                    message: "Interrupted after tools finished. Retry to summarize."
                )
            } else {
                state.phase = .idle
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
        state.activeTask = merged
        state.refreshSummary(for: merged)
        if let plan = merged.pendingPlan {
            planProgress.replace(plan)
        }
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
        if var task = state.activeTask {
            task.pendingPlan = plan
            task.status = .awaitingApproval
            task.updatedAt = .now
            state.activeTask = task
            try? await taskRepository.saveTaskState(task, setActive: true)
            state.refreshSummary(for: task)
        }
        state.phase = .failed(message: message)
    }

    func markFailed(_ message: String) async {
        state.retryState = nil
        state.phase = .failed(message: message)
        guard var task = state.activeTask else { return }
        task.status = .failed
        task.updatedAt = .now
        do {
            try await taskRepository.saveTaskState(task, setActive: true)
            state.activeTask = task
            state.refreshSummary(for: task)
        } catch {
            state.activeTask = task
        }
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

    func taskHasPendingPlan(_ id: UUID) async -> Bool {
        if state.activeTaskID == id { return state.activeTask?.pendingPlan != nil }
        return (try? await taskRepository.hasPendingPlan(taskID: id)) ?? false
    }
}
