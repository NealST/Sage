//
//  TaskRecord.swift
//  Sage
//

import Foundation

nonisolated enum TaskStatus: String, Codable, Sendable {
    case active
    case awaitingApproval
    case completed
    case failed
}

/// A normalized entity available to future context retrieval and local models.
nonisolated struct TaskEntity: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var kind: String
    var value: String

    init(id: UUID = UUID(), kind: String, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

/// An internal unit of work. Tasks are intentionally not exposed as user-managed chats.
nonisolated struct TaskRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var status: TaskStatus
    var summary: String?
    /// Short semantic label (≤20 chars) for task catalog display and routing.
    var topic: String?
    /// One-sentence intent description (≤80 chars) used by the local model router.
    var abstract: String?
    var topicUpdatedAt: Date?
    var events: [AgentEvent]
    var pendingPlan: AgentPlan?
    var entities: [TaskEntity]
    var relatedTaskIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        status: TaskStatus = .active,
        summary: String? = nil,
        topic: String? = nil,
        abstract: String? = nil,
        topicUpdatedAt: Date? = nil,
        events: [AgentEvent] = [],
        pendingPlan: AgentPlan? = nil,
        entities: [TaskEntity] = [],
        relatedTaskIDs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.status = status
        self.summary = summary
        self.topic = topic
        self.abstract = abstract
        self.topicUpdatedAt = topicUpdatedAt
        self.events = events
        self.pendingPlan = pendingPlan
        self.entities = entities
        self.relatedTaskIDs = relatedTaskIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct TaskLibrarySnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var tasks: [TaskRecord]
    var activeTaskID: UUID?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        tasks: [TaskRecord],
        activeTaskID: UUID?
    ) {
        self.schemaVersion = schemaVersion
        self.tasks = tasks
        self.activeTaskID = activeTaskID
    }
}
