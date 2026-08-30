//
//  AgentTaskStore+Lifecycle.swift
//  Sage
//

import Foundation

extension AgentTaskStore {
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
            state.workspaceChanges.reset()
            state.turnInput.reset()
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
        guard !state.isTornDown, var closing = state.activeTask else { return nil }
        contextCompactor?.cancel()
        guard let fork = AgentEventHelpers.forkLastUserInput(
            events: closing.events,
            userEventID: userEventID
        ) else { return nil }
        let oldID = closing.id
        let userQuery = fork.moved.content
        prepareClosingTask(&closing, keptEvents: fork.kept)
        let opening = openingTask(from: closing, userEvent: fork.moved, userQuery: userQuery)
        do {
            try await taskRepository.splitOffTurn(
                closingTask: closing,
                openingTask: opening,
                movedEventIDs: [fork.moved.id]
            )
        } catch {
            state.enterFailed(message: "Could not start a new task: \(error.localizedDescription)")
            return nil
        }
        settleSplitTasks(closing: closing, oldID: oldID, opening: opening)
        await restorePhaseFromActiveTask()
        topicCoordinator?.scheduleTopicGeneration(for: opening)
        return SplitOffTurnResult(newTaskID: opening.id, needsModelTurn: true, userQuery: userQuery)
    }

    func prepareClosingTask(_ closing: inout TaskRecord, keptEvents: [AgentEvent]) {
        closing.events = keptEvents
        closing.pendingPlan = nil
        closing.pendingPrompt = nil
        closing.workPlan = nil
        closing.workingMemory = closing.workingMemory?.validated(against: keptEvents)
        closing.updatedAt = .now
        if !closing.events.isEmpty,
           closing.status == .active || closing.status == .awaitingApproval {
            closing.status = .completed
        }
    }

    func openingTask(from closing: TaskRecord, userEvent: AgentEvent, userQuery: String) -> TaskRecord {
        TaskRecord(
            projectID: closing.projectID ?? state.focusedProject?.id,
            summary: userQuery.isEmpty ? nil : String(userQuery.prefix(160)),
            events: [userEvent],
            workingMemory: nil,
            pendingPlan: nil,
            relatedTaskIDs: [],
            activatedSkillNames: []
        )
    }

    func settleSplitTasks(closing: TaskRecord, oldID: UUID, opening: TaskRecord) {
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
        onTaskClosed?(oldID)
        onActiveTaskChanged?()
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
}
