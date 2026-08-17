//
//  TaskRepository.swift
//  Sage
//

import Foundation

nonisolated struct TaskSummary: Identifiable, Sendable, Equatable {
    let id: UUID
    var status: TaskStatus
    var projectID: UUID?
    var summary: String?
    var topic: String?
    var abstract: String?
    var updatedAt: Date
    /// Set when this row was spawned by a schedule (not a window thread).
    var originScheduleID: UUID? = nil

    /// Whether Recents should treat this as a scheduled run rather than a user thread.
    var isScheduled: Bool { originScheduleID != nil }

    /// Title for Recents / chrome — nil means the row is not worth listing.
    var displayTitle: String? {
        TopicDriftDetector.threadLabel(topic: topic, abstract: abstract, summary: summary)
    }

    /// Recents menu label; scheduled runs are marked so they do not look like user threads.
    var recentsMenuTitle: String {
        guard let title = displayTitle else { return isScheduled ? "Scheduled" : "Task" }
        return isScheduled ? "Scheduled · \(title)" : title
    }

    /// User threads first, then scheduled runs; each group newest-first.
    static func sortedForRecents(_ summaries: [TaskSummary]) -> [TaskSummary] {
        summaries.sorted { lhs, rhs in
            if lhs.isScheduled != rhs.isScheduled {
                return !lhs.isScheduled && rhs.isScheduled
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

/// Workspace payload: focused project + active task + scoped summaries.
nonisolated struct TaskWorkspaceSnapshot: Sendable, Equatable {
    var focusedProject: ProjectRecord?
    var activeTask: TaskRecord?
    var recentSummaries: [TaskSummary]
    var recentProjects: [ProjectRecord]
    var activeTaskID: UUID?
}

/// One dialogue line from a related task (user or plain assistant text).
nonisolated struct RelatedDialogueLine: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case user
        case assistant
    }

    let kind: Kind
    let content: String
}

/// Lean related-task payload for model context (no full event/tool-call graph).
nonisolated struct RelatedTaskContextSnippet: Sendable, Equatable {
    let id: UUID
    let projectID: UUID?
    let topic: String?
    let summary: String?
    let abstract: String?
    /// Chronological tail of user / plain-assistant messages (no tool proposals).
    let recentDialogue: [RelatedDialogueLine]
}

nonisolated protocol TaskRepository: Sendable {
    /// Workspace for one scope (`nil` = General). Does not read or write global focus.
    func loadScopedWorkspace(projectID: UUID?) async throws -> TaskWorkspaceSnapshot
    func loadTask(id: UUID) async throws -> TaskRecord?
    /// Task row + relations only — no events, tool calls, or plan graph.
    func loadTaskMetadata(id: UUID) async throws -> TaskRecord?
    func loadProject(id: UUID) async throws -> ProjectRecord?
    func listRecentProjects(limit: Int) async throws -> [ProjectRecord]
    /// Metadata + last N dialogue lines for related-task appendix (scoped, no full task load).
    func loadRelatedContextSnippets(
        ids: [UUID],
        projectID: UUID?
    ) async throws -> [RelatedTaskContextSnippet]
    /// Lightweight check — does not load events or plan steps.
    func hasPendingPlan(taskID: UUID) async throws -> Bool
    /// Keep IDs that exist and belong to `projectID` (nil = General), preserving order.
    func filterTaskIDs(_ ids: [UUID], projectID: UUID?) async throws -> [UUID]
    /// Inserts or updates task metadata/entities/relations/plan. Does not rewrite event history.
    func saveTaskState(_ task: TaskRecord, setActive: Bool) async throws
    /// Updates one plan step's status/result without rewriting the plan graph.
    func updatePlanStep(
        taskID: UUID,
        stepID: UUID,
        status: StepStatus,
        result: String?
    ) async throws
    /// Atomically append/delete events and save task state.
    func mutateTask(
        _ task: TaskRecord,
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        setActive: Bool
    ) async throws
    /// Move a suffix of events (and optional plan) onto a new task in one transaction.
    func splitOffTurn(
        closingTask: TaskRecord,
        openingTask: TaskRecord,
        movedEventIDs: [UUID]
    ) async throws
    /// Updates only topic fields — safe against concurrent plan/event writes.
    func updateTopic(
        taskID: UUID,
        topic: String,
        abstract: String,
        topicUpdatedAt: Date
    ) async throws
    /// Deletes a task and cascaded rows (events, plans, relations).
    func deleteTask(id: UUID) async throws
    /// Sets focus + active task together (enforces project/task scope invariant).
    func setFocus(projectID: UUID?, activeTaskID: UUID?) async throws
    /// Open an existing directory as a project (reuse by root_path). Does not change window focus.
    func openProject(rootURL: URL, displayName: String?) async throws -> ProjectRecord
    /// Create a directory under parent, optionally `git init`, then open as project.
    func createProject(
        parentURL: URL,
        name: String,
        gitInit: Bool
    ) async throws -> ProjectRecord
    /// Persist last-active task for a project (call when leaving focus).
    func setProjectLastActiveTask(projectID: UUID, taskID: UUID?) async throws
    /// Remember which General task to restore when leaving a project.
    func setLastGeneralTaskID(_ taskID: UUID?) async throws
    func lastGeneralTaskID() async throws -> UUID?
    /// Update per-scope last-active pointers without stomping another window's global focus.
    func rememberScopeActiveTask(projectID: UUID?, taskID: UUID) async throws
    func eraseAllData() async throws

    func listSchedules() async throws -> [ScheduleRecord]
    func loadSchedule(id: UUID) async throws -> ScheduleRecord?
    func upsertSchedule(_ schedule: ScheduleRecord) async throws
    func deleteSchedule(id: UUID) async throws
    func dueSchedules(at date: Date) async throws -> [ScheduleRecord]
    func insertScheduleRun(
        id: UUID,
        scheduleID: UUID,
        startedAt: Date,
        endedAt: Date?,
        exitCode: Int32?,
        outputExcerpt: String?
    ) async throws
    /// Most recent run log for a schedule, if any.
    func latestScheduleRun(scheduleID: UUID) async throws -> ScheduleRunRecord?
}
