//
//  AgentTaskStore+Restore.swift
//  Sage
//

import Foundation

extension AgentTaskStore {
    func restorePhaseFromActiveTask() async {
        guard let task = state.activeTask else {
            state.enterIdle()
            state.lastAssistantText = nil
            planProgress.clear()
            return
        }
        restoreBaseState(from: task)
        if restorePendingPrompt(from: task) { return }
        await restorePendingPlan(from: task)
    }

    func restoreBaseState(from task: TaskRecord) {
        state.activatedSkillNames = task.activatedSkillNames
        state.pendingPrompt = task.pendingPrompt
        state.lastAssistantText = task.events.last { event in
            event.kind == .assistantResponse && (event.toolCalls?.isEmpty ?? true)
        }?.content
    }

    func restorePendingPrompt(from task: TaskRecord) -> Bool {
        if case .toolRoundLimit = task.pendingPrompt {
            restoreToolRoundLimitPlan(from: task)
            state.enterAwaitingConfirmation()
            return true
        }
        if case .reviewFailed = task.pendingPrompt {
            state.enterAwaitingConfirmation()
            return true
        }
        if case .toolApproval = task.pendingPrompt {
            if var plan = task.pendingPlan {
                normalizeRestoredPlan(&plan, events: task.events)
                var updated = task
                updated.pendingPlan = plan
                state.activeTask = updated
                planProgress.replace(plan)
                state.enterAwaitingConfirmation()
                return true
            }
            state.clearPendingPrompt()
        }
        return false
    }

    func restoreToolRoundLimitPlan(from task: TaskRecord) {
        guard var plan = task.pendingPlan else {
            planProgress.clear()
            return
        }
        normalizeRestoredPlan(&plan, events: task.events)
        if plan.steps.contains(where: { $0.status != .succeeded && $0.status != .skipped }) {
            var updated = task
            updated.pendingPlan = plan
            state.activeTask = updated
            planProgress.replace(plan)
        } else {
            planProgress.clear()
        }
    }

    func restorePendingPlan(from task: TaskRecord) async {
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
        let unfinished = plan.steps.contains { step in
            step.status != .succeeded && step.status != .skipped
        }
        if unfinished {
            updated.pendingPlan = plan
            state.activeTask = updated
            planProgress.replace(plan)
            state.enterAwaitingConfirmation()
            return
        }
        updated.pendingPlan = nil
        state.activeTask = updated
        planProgress.clear()
        try? await taskRepository.saveTaskState(updated, setActive: setsScopeActive)
        state.refreshSummary(for: updated)
        if updated.events.last?.kind == .toolResult {
            state.enterFailed(message: "Interrupted after tools finished. Retry to summarize.")
        } else {
            state.enterIdle()
        }
    }

    func normalizeRestoredPlan(_ plan: inout AgentPlan, events: [AgentEvent]) {
        for index in plan.steps.indices {
            if let result = events.last(where: { event in
                event.kind == .toolResult && event.toolCallID == plan.steps[index].toolCallID
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
