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
}

/// Workspace payload: focused project + active task + scoped summaries.
nonisolated struct TaskWorkspaceSnapshot: Sendable, Equatable {
    var focusedProject: ProjectRecord?
    var activeTask: TaskRecord?
    var recentSummaries: [TaskSummary]
    var recentProjects: [ProjectRecord]
    var activeTaskID: UUID?
}

nonisolated protocol TaskRepository: Sendable {
    func loadWorkspace() async throws -> TaskWorkspaceSnapshot
    func loadTask(id: UUID) async throws -> TaskRecord?
    func loadProject(id: UUID) async throws -> ProjectRecord?
    func listRecentProjects(limit: Int) async throws -> [ProjectRecord]
    /// Lightweight check — does not load events or plan steps.
    func hasPendingPlan(taskID: UUID) async throws -> Bool
    /// Inserts or updates task metadata/entities/relations/plan. Does not rewrite event history.
    func saveTaskState(_ task: TaskRecord, setActive: Bool) async throws
    /// Atomically append/delete events and save task state.
    func mutateTask(
        _ task: TaskRecord,
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        setActive: Bool
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
    /// Open an existing directory as a project (reuse by root_path) and focus it.
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
    func eraseAllData() async throws
}
