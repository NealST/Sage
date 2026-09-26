//
//  projects.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/projects.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Project CRUD SQL throws until a state pool exists. Cursor encode/parse
//  helpers are implemented in memory. Reuses `model/project.swift` types.
//

import Foundation

extension StateRuntime {
    public func setThreadProject(
        threadId: String,
        projectId: String?
    ) async throws -> String?? {
        _ = threadId
        _ = projectId
        throw StateRuntimeError.sqliteUnavailable("projects")
    }

    public func listProjects(
        cursor: String?,
        limit: Int,
        sortKey: ProjectSortKey,
        sortDirection: SortDirection
    ) async throws -> ProjectsPage {
        if limit == 0 {
            throw StateRuntimeError.invalidInput("project limit must be positive")
        }
        if limit == Int.max {
            throw StateRuntimeError.invalidInput("project limit overflow")
        }
        if let cursor {
            _ = try parseProjectCursor(cursor, sortKey: sortKey, direction: sortDirection)
        }
        throw StateRuntimeError.sqliteUnavailable("projects")
    }

    public func getProject(id: String) async throws -> Project? {
        _ = id
        throw StateRuntimeError.sqliteUnavailable("projects")
    }

    public func getProjectByIdempotencyKey(
        idempotencyKey: String
    ) async throws -> Project? {
        _ = idempotencyKey
        throw StateRuntimeError.sqliteUnavailable("projects")
    }

    public func createProject(
        name: String,
        roots: [ProjectRoot],
        metadata: [String: String],
        threadIds: [String],
        idempotencyKey: String
    ) async throws -> CreatedProject {
        _ = name
        _ = roots
        _ = metadata
        _ = threadIds
        _ = idempotencyKey
        throw StateRuntimeError.sqliteUnavailable("projects")
    }

    public func updateProject(
        id: String,
        name: String?,
        roots: [ProjectRoot]?,
        metadata: [String: String]?
    ) async throws -> (Project, Bool)? {
        _ = id
        _ = name
        _ = roots
        _ = metadata
        throw StateRuntimeError.sqliteUnavailable("projects")
    }

    /// Move a project before another project, or append it when the anchor is absent.
    ///
    /// Returns nil when the moved project does not exist and `false` for a no-op.
    public func moveProject(
        projectId: String,
        beforeProjectId: String?
    ) async throws -> Bool? {
        _ = projectId
        _ = beforeProjectId
        throw StateRuntimeError.sqliteUnavailable("projects")
    }

    public func deleteProject(
        id: String
    ) async throws -> ([String], [String])? {
        _ = id
        throw StateRuntimeError.sqliteUnavailable("projects")
    }
}

func projectCursor(
    _ project: Project,
    sortKey: ProjectSortKey,
    direction: SortDirection
) -> String {
    if sortKey == .position && direction == .asc {
        // Retain the existing format for clients reconnecting to an older server.
        return "\(project.position)|\(project.id)"
    }
    let key: String
    let value: String
    switch sortKey {
    case .position:
        key = "position"
        value = String(project.position)
    case .recencyAt:
        key = "recencyAt"
        value = project.recencyAtMs.map(String.init) ?? "null"
    }
    let directionText = direction == .asc ? "asc" : "desc"
    return "v1|\(key)|\(directionText)|\(value)|\(project.id)"
}

func parseProjectCursor(
    _ cursor: String,
    sortKey: ProjectSortKey,
    direction: SortDirection
) throws -> (Int64?, String) {
    let invalid = StateRuntimeError.invalidInput(
        "invalid project cursor: malformed or mismatched sort anchor"
    )
    if cursor.count > 128 {
        throw invalid
    }
    let parts = cursor.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let key = sortKey == .position ? "position" : "recencyAt"
    let order = direction == .asc ? "asc" : "desc"
    let value: String
    let id: String
    if parts.count == 2, sortKey == .position, direction == .asc {
        value = parts[0]
        id = parts[1]
    } else if parts.count == 5, parts[0] == "v1", parts[1] == key, parts[2] == order {
        value = parts[3]
        id = parts[4]
    } else {
        throw invalid
    }
    let parsedValue: Int64?
    if value == "null" && sortKey == .recencyAt {
        parsedValue = nil
    } else {
        guard let parsed = Int64(value), String(parsed) == value else {
            throw invalid
        }
        if sortKey == .position && parsed < 0 {
            throw invalid
        }
        parsedValue = parsed
    }
    guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else {
        throw invalid
    }
    return (parsedValue, id)
}
