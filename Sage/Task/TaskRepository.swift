//
//  TaskRepository.swift
//  Sage
//

import Foundation

nonisolated struct TaskSummary: Identifiable, Sendable, Equatable {
    let id: UUID
    var status: TaskStatus
    var summary: String?
    var topic: String?
    var abstract: String?
    var updatedAt: Date
}

/// Workspace payload: full active task + lightweight summaries for retrieval.
nonisolated struct TaskWorkspaceSnapshot: Sendable, Equatable {
    var activeTask: TaskRecord?
    var recentSummaries: [TaskSummary]
    var activeTaskID: UUID?
}

nonisolated protocol TaskRepository: Sendable {
    func loadWorkspace() async throws -> TaskWorkspaceSnapshot
    func loadTask(id: UUID) async throws -> TaskRecord?
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
    func setActiveTaskID(_ taskID: UUID?) async throws
    func eraseAllData() async throws
}
