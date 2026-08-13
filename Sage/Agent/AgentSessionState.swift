//
//  AgentSessionState.swift
//  Sage
//
//  Mutable session fields observed by SwiftUI. Collaborators mutate this
//  directly instead of poking AgentRuntime through a Host protocol mesh.
//

import Foundation

@MainActor
@Observable
final class AgentSessionState {
    /// Full active task only — other tasks stay as lightweight summaries.
    var activeTask: TaskRecord?
    var recentSummaries: [TaskSummary] = []
    var activeTaskID: UUID?
    /// Focused code project (`nil` = General).
    var focusedProject: ProjectRecord?
    var recentProjects: [ProjectRecord] = []
    var phase: AgentPhase = .idle
    var lastAssistantText: String?
    /// Retry countdown — non-nil while waiting to retry a transient error.
    var retryState: RetryDisplayState?
    /// Cumulative token usage for the current task (cleared on beginNewTask).
    var tokenUsage = TokenUsage()
    /// Soft chip when Sage resumes related prior work (not ordinary continuity).
    var contextHint: String?
    var isBusy = false
    /// After dismissing the context chip, the next submit starts a clean task.
    var forceFreshOnNextSubmit = false
    /// Skills already loaded via `load_skill` / slash activation in this task.
    var activatedSkillNames: Set<String> = []
    /// Set when the owning window is closing — blocks further DB commits.
    var isTornDown = false

    var events: [AgentEvent] {
        activeTask?.events ?? []
    }

    var hasPendingPlan: Bool {
        if case .awaitingConfirmation = phase { return true }
        return activeTask?.pendingPlan != nil
    }

    var pathGuardPolicy: PathGuard.Policy {
        if let focusedProject {
            return .project(root: focusedProject.rootURL)
        }
        return .home
    }

    var focusTitle: String {
        focusedProject?.name ?? "General"
    }

    func clearTokenUsage() {
        tokenUsage = TokenUsage()
    }

    func addTokenUsage(_ usage: TokenUsage) {
        guard usage.input > 0 || usage.output > 0 else { return }
        tokenUsage.input += usage.input
        tokenUsage.output += usage.output
    }

    func refreshSummary(for task: TaskRecord) {
        guard task.projectID == focusedProject?.id else { return }
        let summary = TaskSummary(
            id: task.id,
            status: task.status,
            projectID: task.projectID,
            summary: task.summary,
            topic: task.topic,
            abstract: task.abstract,
            updatedAt: task.updatedAt
        )
        if let index = recentSummaries.firstIndex(where: { $0.id == task.id }) {
            recentSummaries[index] = summary
        } else {
            recentSummaries.insert(summary, at: 0)
        }
        recentSummaries.sort { $0.updatedAt > $1.updatedAt }
    }

    func removeSummary(id: UUID) {
        recentSummaries.removeAll { $0.id == id }
    }

    func adoptActiveTaskTopic(_ result: TopicResult, stampedAt: Date) {
        guard var task = activeTask else { return }
        task.topic = result.topic
        task.abstract = result.abstract
        task.topicUpdatedAt = stampedAt
        task.updatedAt = stampedAt
        activeTask = task
        refreshSummary(for: task)
    }

    func updateRecentSummaryTopic(taskID: UUID, result: TopicResult, stampedAt: Date) {
        guard let index = recentSummaries.firstIndex(where: { $0.id == taskID }) else { return }
        let prior = recentSummaries[index]
        recentSummaries[index] = TaskSummary(
            id: prior.id,
            status: prior.status,
            projectID: prior.projectID,
            summary: prior.summary,
            topic: result.topic,
            abstract: result.abstract,
            updatedAt: stampedAt
        )
        recentSummaries.sort { $0.updatedAt > $1.updatedAt }
    }

    /// Sync phase with an in-memory plan without embedding the plan graph in `phase`.
    func enterAwaitingConfirmation() {
        phase = .awaitingConfirmation
    }

    func enterExecuting() {
        phase = .executing
    }
}
