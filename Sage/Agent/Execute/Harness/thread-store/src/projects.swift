//
//  projects.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/projects.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `ProjectSortKey` stands in for the unported CodexState model.
//  In-memory create/read/list/update/move/delete lives on
//  `InMemoryThreadStore`.
//

import Foundation

public enum ProjectSortKey: String, Codable, Equatable, Sendable {
    case position = "Position"
    case recencyAt = "RecencyAt"
}

public struct StoredProjectRoot: Codable, Equatable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct StoredProject: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var roots: [StoredProjectRoot]
    public var metadata: [String: String]
    public var position: Int64
    public var createdAtMs: Int64
    public var updatedAtMs: Int64
    public var recencyAtMs: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, roots, metadata, position
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case recencyAtMs = "recency_at_ms"
    }

    public init(
        id: String,
        name: String,
        roots: [StoredProjectRoot],
        metadata: [String: String],
        position: Int64,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        recencyAtMs: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.roots = roots
        self.metadata = metadata
        self.position = position
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.recencyAtMs = recencyAtMs
    }
}

public struct StoredProjectsPage: Codable, Equatable, Sendable {
    public var projects: [StoredProject]
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case projects
        case nextCursor = "next_cursor"
    }

    public init(projects: [StoredProject], nextCursor: String? = nil) {
        self.projects = projects
        self.nextCursor = nextCursor
    }
}

public struct ListProjectsParams: Codable, Equatable, Sendable {
    public var cursor: String?
    public var limit: Int
    public var sortKey: ProjectSortKey
    public var sortDirection: SortDirection

    enum CodingKeys: String, CodingKey {
        case cursor, limit
        case sortKey = "sort_key"
        case sortDirection = "sort_direction"
    }

    public init(
        cursor: String? = nil,
        limit: Int,
        sortKey: ProjectSortKey,
        sortDirection: SortDirection
    ) {
        self.cursor = cursor
        self.limit = limit
        self.sortKey = sortKey
        self.sortDirection = sortDirection
    }
}

public struct CreateProjectParams: Codable, Equatable, Sendable {
    public var name: String
    public var roots: [StoredProjectRoot]
    public var metadata: [String: String]
    public var threadIds: [String]
    public var idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case name, roots, metadata
        case threadIds = "thread_ids"
        case idempotencyKey = "idempotency_key"
    }

    public init(
        name: String,
        roots: [StoredProjectRoot],
        metadata: [String: String],
        threadIds: [String],
        idempotencyKey: String
    ) {
        self.name = name
        self.roots = roots
        self.metadata = metadata
        self.threadIds = threadIds
        self.idempotencyKey = idempotencyKey
    }
}

public struct CreatedProject: Codable, Equatable, Sendable {
    public var project: StoredProject
    public var created: Bool

    public init(project: StoredProject, created: Bool) {
        self.project = project
        self.created = created
    }
}

public struct UpdateProjectParams: Codable, Equatable, Sendable {
    public var projectId: String
    public var name: String?
    public var roots: [StoredProjectRoot]?
    public var metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, roots, metadata
        case projectId = "project_id"
    }

    public init(
        projectId: String,
        name: String? = nil,
        roots: [StoredProjectRoot]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.projectId = projectId
        self.name = name
        self.roots = roots
        self.metadata = metadata
    }
}

public struct MoveProjectParams: Codable, Equatable, Sendable {
    public var projectId: String
    public var beforeProjectId: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case beforeProjectId = "before_project_id"
    }

    public init(projectId: String, beforeProjectId: String? = nil) {
        self.projectId = projectId
        self.beforeProjectId = beforeProjectId
    }
}

public enum ProjectMoveOutcome: String, Codable, Equatable, Sendable {
    case unchanged = "Unchanged"
    case moved = "Moved"
}

public struct UpdatedProject: Codable, Equatable, Sendable {
    public var project: StoredProject
    public var changed: Bool

    public init(project: StoredProject, changed: Bool) {
        self.project = project
        self.changed = changed
    }
}

public struct DeletedProject: Codable, Equatable, Sendable {
    public var affectedActiveThreadIds: [String]
    public var affectedArchivedThreadIds: [String]

    enum CodingKeys: String, CodingKey {
        case affectedActiveThreadIds = "affected_active_thread_ids"
        case affectedArchivedThreadIds = "affected_archived_thread_ids"
    }

    public init(affectedActiveThreadIds: [String], affectedArchivedThreadIds: [String]) {
        self.affectedActiveThreadIds = affectedActiveThreadIds
        self.affectedArchivedThreadIds = affectedArchivedThreadIds
    }
}
