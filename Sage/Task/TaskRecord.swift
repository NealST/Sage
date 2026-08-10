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
    /// `nil` = General (no project). Non-nil = bound to that project.
    var projectID: UUID?
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
    /// Skills activated in this task (persisted so they survive task switches).
    var activatedSkillNames: Set<String>
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        status: TaskStatus = .active,
        projectID: UUID? = nil,
        summary: String? = nil,
        topic: String? = nil,
        abstract: String? = nil,
        topicUpdatedAt: Date? = nil,
        events: [AgentEvent] = [],
        pendingPlan: AgentPlan? = nil,
        entities: [TaskEntity] = [],
        relatedTaskIDs: [UUID] = [],
        activatedSkillNames: Set<String> = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.status = status
        self.projectID = projectID
        self.summary = summary
        self.topic = topic
        self.abstract = abstract
        self.topicUpdatedAt = topicUpdatedAt
        self.events = events
        self.pendingPlan = pendingPlan
        self.entities = entities
        self.relatedTaskIDs = relatedTaskIDs
        self.activatedSkillNames = activatedSkillNames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        status = try container.decode(TaskStatus.self, forKey: .status)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        abstract = try container.decodeIfPresent(String.self, forKey: .abstract)
        topicUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .topicUpdatedAt)
        events = try container.decode([AgentEvent].self, forKey: .events)
        pendingPlan = try container.decodeIfPresent(AgentPlan.self, forKey: .pendingPlan)
        entities = try container.decodeIfPresent([TaskEntity].self, forKey: .entities) ?? []
        relatedTaskIDs = try container.decodeIfPresent([UUID].self, forKey: .relatedTaskIDs) ?? []
        activatedSkillNames = try container.decodeIfPresent(Set<String>.self, forKey: .activatedSkillNames) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, projectID, summary, topic, abstract, topicUpdatedAt
        case events, pendingPlan, entities, relatedTaskIDs, activatedSkillNames
        case createdAt, updatedAt
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
