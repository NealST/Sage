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

/// A normalized entity available to future context retrieval.
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

    /// An internal unit of work. Tasks are the current thread in a window,
    /// not a user-managed chat list.
nonisolated struct TaskRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var status: TaskStatus
    /// `nil` = General (no project). Non-nil = bound to that project.
    var projectID: UUID?
    var summary: String?
    /// Short semantic label (≤20 chars) for task catalog display and routing.
    var topic: String?
    /// One-sentence intent description (≤80 chars) used for routing and catalog display.
    var abstract: String?
    var topicUpdatedAt: Date?
    var events: [AgentEvent]
    /// Strategy from the plan sub-agent (intent + approach). Not tool steps.
    var workPlan: WorkPlan?
    /// Model-only fold of older turns. Nil means the prompt still uses raw events.
    /// Never shown in the transcript, Recents, or chrome.
    var workingMemory: TaskWorkingMemory?
    var pendingPlan: AgentPlan?
    var entities: [TaskEntity]
    var relatedTaskIDs: [UUID]
    /// Skills activated in this task (persisted so they survive task switches).
    var activatedSkillNames: Set<String>
    /// Plan already judged persist (or the turn finished without needing a backfill).
    var skillPersistConsidered: Bool
    /// Set when this task was spawned by a schedule runner (not a window thread).
    var originScheduleID: UUID?
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
        workPlan: WorkPlan? = nil,
        workingMemory: TaskWorkingMemory? = nil,
        pendingPlan: AgentPlan? = nil,
        entities: [TaskEntity] = [],
        relatedTaskIDs: [UUID] = [],
        activatedSkillNames: Set<String> = [],
        skillPersistConsidered: Bool = false,
        originScheduleID: UUID? = nil,
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
        self.workPlan = workPlan
        self.workingMemory = workingMemory
        self.pendingPlan = pendingPlan
        self.entities = entities
        self.relatedTaskIDs = relatedTaskIDs
        self.activatedSkillNames = activatedSkillNames
        self.skillPersistConsidered = skillPersistConsidered
        self.originScheduleID = originScheduleID
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
        workPlan = try container.decodeIfPresent(WorkPlan.self, forKey: .workPlan)
        workingMemory = try container.decodeIfPresent(TaskWorkingMemory.self, forKey: .workingMemory)
        pendingPlan = try container.decodeIfPresent(AgentPlan.self, forKey: .pendingPlan)
        entities = try container.decodeIfPresent([TaskEntity].self, forKey: .entities) ?? []
        relatedTaskIDs = try container.decodeIfPresent([UUID].self, forKey: .relatedTaskIDs) ?? []
        activatedSkillNames = try container.decodeIfPresent(Set<String>.self, forKey: .activatedSkillNames) ?? []
        skillPersistConsidered = try container.decodeIfPresent(Bool.self, forKey: .skillPersistConsidered) ?? false
        originScheduleID = try container.decodeIfPresent(UUID.self, forKey: .originScheduleID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(topic, forKey: .topic)
        try container.encodeIfPresent(abstract, forKey: .abstract)
        try container.encodeIfPresent(topicUpdatedAt, forKey: .topicUpdatedAt)
        try container.encode(events, forKey: .events)
        try container.encodeIfPresent(workPlan, forKey: .workPlan)
        try container.encodeIfPresent(workingMemory, forKey: .workingMemory)
        try container.encodeIfPresent(pendingPlan, forKey: .pendingPlan)
        try container.encode(entities, forKey: .entities)
        try container.encode(relatedTaskIDs, forKey: .relatedTaskIDs)
        try container.encode(activatedSkillNames, forKey: .activatedSkillNames)
        try container.encode(skillPersistConsidered, forKey: .skillPersistConsidered)
        try container.encodeIfPresent(originScheduleID, forKey: .originScheduleID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, projectID, summary, topic, abstract, topicUpdatedAt
        case events, workPlan, workingMemory, pendingPlan, entities, relatedTaskIDs, activatedSkillNames
        case skillPersistConsidered
        case originScheduleID
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
