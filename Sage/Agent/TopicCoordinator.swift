//
//  TopicCoordinator.swift
//  Sage
//
//  Async topic / abstract generation for tasks (formerly part of TaskRoutingCoordinator).
//

import Foundation

@MainActor
final class TopicCoordinator {
    private let state: AgentSessionState
    private let taskRepository: any TaskRepository
    private var topicGenerationTaskIDs: Set<UUID> = []

    init(
        state: AgentSessionState,
        taskRepository: any TaskRepository
    ) {
        self.state = state
        self.taskRepository = taskRepository
    }

    func generateTopicIfNeeded(for task: TaskRecord?) {
        guard let task else { return }
        scheduleTopicGeneration(for: task)
    }

    func scheduleTopicGeneration(for task: TaskRecord) {
        guard task.topic == nil, !task.events.isEmpty else { return }
        guard !topicGenerationTaskIDs.contains(task.id) else { return }
        topicGenerationTaskIDs.insert(task.id)

        let taskID = task.id
        let events = task.events
        Task(priority: .utility) { [weak self] in
            let result = TopicGenerator.generate(from: events)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.topicGenerationTaskIDs.remove(taskID)
                if let result {
                    self.applyTopicResult(result, for: taskID)
                }
            }
        }
    }

    /// Refresh topic/abstract when resuming a prior task with new input.
    func scheduleTopicRefreshOnResume(
        taskID: UUID,
        existingTopic: String,
        existingAbstract: String,
        newInput: String
    ) {
        Task(priority: .utility) { [weak self] in
            if let updated = TopicGenerator.update(
                existingTopic: existingTopic,
                existingAbstract: existingAbstract,
                newInput: newInput
            ) {
                await MainActor.run { [weak self] in
                    self?.applyTopicResult(updated, for: taskID)
                }
            }
        }
    }

    private func applyTopicResult(_ result: TopicResult, for taskID: UUID) {
        guard !state.isTornDown else { return }
        let stampedAt = Date.now

        if let active = state.activeTask, active.id == taskID {
            state.adoptActiveTaskTopic(result, stampedAt: stampedAt)
        } else {
            state.updateRecentSummaryTopic(taskID: taskID, result: result, stampedAt: stampedAt)
        }

        let repository = taskRepository
        Task { [weak self] in
            guard let self, !self.state.isTornDown else { return }
            try? await repository.updateTopic(
                taskID: taskID,
                topic: result.topic,
                abstract: result.abstract,
                topicUpdatedAt: stampedAt
            )
        }
    }
}
