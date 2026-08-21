//
//  GRDBTaskRepository.swift
//  Sage
//

import Foundation
import GRDB

actor GRDBTaskRepository: TaskRepository {
    let databaseURL: URL
    let legacyJSONURL: URL
    var databasePool: DatabasePool?

    init() {
        _ = AppSupportPaths.sageDirectory(createIfNeeded: true)
        databaseURL = AppSupportPaths.sqliteDatabaseURL()
        legacyJSONURL = AppSupportPaths.legacyTasksJSONURL()
    }

    /// Isolated database for tests. Does not touch Application Support.
    init(databaseURL: URL, legacyJSONURL: URL) {
        self.databaseURL = databaseURL
        self.legacyJSONURL = legacyJSONURL
    }

    func loadScopedWorkspace(projectID: UUID?) throws -> TaskWorkspaceSnapshot {
        let pool = try database()
        return try pool.read { database in
            try loadScopedWorkspace(projectID: projectID, database: database)
        }
    }

    private func loadScopedWorkspace(projectID: UUID?, database: Database) throws -> TaskWorkspaceSnapshot {
        let focusedProject = try projectID.flatMap { try loadProject(id: $0, database: database) }
        let recentSummaries = try loadRecentSummaries(projectID: projectID, database: database)
        let recentProjects = try loadRecentProjects(limit: 12, database: database)
        let preferredActiveID = try preferredActiveTaskID(focusedProject: focusedProject, database: database)
        let activeTask = try loadPreferredActiveTask(
            preferredActiveID: preferredActiveID,
            projectID: projectID,
            recentSummaries: recentSummaries,
            database: database
        )
        return TaskWorkspaceSnapshot(
            focusedProject: focusedProject,
            activeTask: activeTask,
            recentSummaries: recentSummaries,
            recentProjects: recentProjects,
            activeTaskID: activeTask?.id
        )
    }

    private func loadRecentSummaries(projectID: UUID?, database: Database) throws -> [TaskSummary] {
        let sql = """
        SELECT id, status, project_id, summary, topic, abstract, updated_at, origin_schedule_id
        FROM tasks
        WHERE \(projectID == nil ? "project_id IS NULL" : "project_id = ?")
          AND origin_schedule_id IS NULL
        ORDER BY updated_at DESC
        LIMIT 40
        """
        let rows: [Row]
        if let projectID {
            rows = try Row.fetchAll(database, sql: sql, arguments: [projectID.uuidString])
        } else {
            rows = try Row.fetchAll(database, sql: sql)
        }
        return rows.compactMap { Self.taskSummary(from: $0) }
    }

    private func preferredActiveTaskID(
        focusedProject: ProjectRecord?,
        database: Database
    ) throws -> UUID? {
        if let project = focusedProject {
            return project.lastActiveTaskID
        }
        let raw = try String.fetchOne(
            database,
            sql: "SELECT last_general_task_id FROM app_state WHERE singleton = 1"
        )
        return raw.flatMap(UUID.init(uuidString:))
    }

    private func loadPreferredActiveTask(
        preferredActiveID: UUID?,
        projectID: UUID?,
        recentSummaries: [TaskSummary],
        database: Database
    ) throws -> TaskRecord? {
        if let preferredActiveID,
           let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM tasks WHERE id = ?",
            arguments: [preferredActiveID.uuidString]
           ),
           let loaded = try loadTask(from: row, database: database),
           loaded.projectID == projectID {
            return loaded
        }
        guard let first = recentSummaries.first,
              let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM tasks WHERE id = ?",
                arguments: [first.id.uuidString]
              )
        else { return nil }
        return try loadTask(from: row, database: database)
    }
}
