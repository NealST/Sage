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

    func loadScopedWorkspace(projectID: UUID?) throws -> TaskWorkspaceSnapshot {
        let pool = try database()
        return try pool.read { db in
            try loadScopedWorkspace(projectID: projectID, database: db)
        }
    }

    private func loadScopedWorkspace(projectID: UUID?, database db: Database) throws -> TaskWorkspaceSnapshot {
        let focusedProject: ProjectRecord?
        if let projectID {
            focusedProject = try loadProject(id: projectID, database: db)
        } else {
            focusedProject = nil
        }

        let summaryRows: [Row]
        if let projectID {
            summaryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, status, project_id, summary, topic, abstract, updated_at, origin_schedule_id
                FROM tasks
                WHERE project_id = ?
                ORDER BY CASE WHEN origin_schedule_id IS NULL THEN 0 ELSE 1 END, updated_at DESC
                LIMIT 40
                """,
                arguments: [projectID.uuidString]
            )
        } else {
            summaryRows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, status, project_id, summary, topic, abstract, updated_at, origin_schedule_id
                FROM tasks
                WHERE project_id IS NULL
                ORDER BY CASE WHEN origin_schedule_id IS NULL THEN 0 ELSE 1 END, updated_at DESC
                LIMIT 40
                """
            )
        }

        let recentSummaries = TaskSummary.sortedForRecents(
            summaryRows.compactMap { row -> TaskSummary? in
                Self.taskSummary(from: row)
            }
        )

        let recentProjects = try loadRecentProjects(limit: 12, database: db)

        let preferredActiveID: UUID?
        if let project = focusedProject {
            preferredActiveID = project.lastActiveTaskID
        } else {
            let raw = try String.fetchOne(
                db,
                sql: "SELECT last_general_task_id FROM app_state WHERE singleton = 1"
            )
            preferredActiveID = raw.flatMap(UUID.init(uuidString:))
        }

        let activeTask: TaskRecord?
        if let preferredActiveID,
           let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM tasks WHERE id = ?",
            arguments: [preferredActiveID.uuidString]
           ),
           let loaded = try loadTask(from: row, database: db),
           loaded.projectID == projectID {
            activeTask = loaded
        } else if let first = recentSummaries.first(where: { !$0.isScheduled }),
                  let row = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM tasks WHERE id = ?",
                    arguments: [first.id.uuidString]
                  ) {
            activeTask = try loadTask(from: row, database: db)
        } else {
            activeTask = nil
        }

        return TaskWorkspaceSnapshot(
            focusedProject: focusedProject,
            activeTask: activeTask,
            recentSummaries: recentSummaries,
            recentProjects: recentProjects,
            activeTaskID: activeTask?.id
        )
    }

    func loadProject(id: UUID) throws -> ProjectRecord? {
        let pool = try database()
        return try pool.read { db in
            try loadProject(id: id, database: db)
        }
    }

    func listRecentProjects(limit: Int) throws -> [ProjectRecord] {
        let pool = try database()
        return try pool.read { db in
            try loadRecentProjects(limit: limit, database: db)
        }
    }

    func loadTask(id: UUID) throws -> TaskRecord? {
        let pool = try database()
        return try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try loadTask(from: row, database: db, includeHistory: true)
        }
    }

    func loadTaskMetadata(id: UUID) throws -> TaskRecord? {
        let pool = try database()
        return try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try loadTask(from: row, database: db, includeHistory: false)
        }
    }

    func hasPendingPlan(taskID: UUID) throws -> Bool {
        let pool = try database()
        return try pool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS (SELECT 1 FROM plans WHERE task_id = ?)",
                arguments: [taskID.uuidString]
            ) ?? false
        }
    }

    func filterTaskIDs(_ ids: [UUID], projectID: UUID?) throws -> [UUID] {
        guard !ids.isEmpty else { return [] }
        let pool = try database()
        return try pool.read { db in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
            var sql = """
            SELECT id FROM tasks
            WHERE id IN (\(placeholders))
            """
            var arguments: [any DatabaseValueConvertible] = ids.map(\.uuidString)
            if let projectID {
                sql += " AND project_id = ?"
                arguments.append(projectID.uuidString)
            } else {
                sql += " AND project_id IS NULL"
            }
            let found = try String.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            let allowed = Set(found)
            // Preserve caller order and drop duplicates.
            var result: [UUID] = []
            result.reserveCapacity(ids.count)
            for id in ids where allowed.contains(id.uuidString) && !result.contains(id) {
                result.append(id)
            }
            return result
        }
    }

    func loadRelatedContextSnippets(
        ids: [UUID],
        projectID: UUID?
    ) throws -> [RelatedTaskContextSnippet] {
        guard !ids.isEmpty else { return [] }
        let pool = try database()
        return try pool.read { db in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
            var taskSQL = """
            SELECT id, project_id, summary, topic, abstract
            FROM tasks
            WHERE id IN (\(placeholders))
            """
            var taskArgs: [any DatabaseValueConvertible] = ids.map(\.uuidString)
            if let projectID {
                taskSQL += " AND project_id = ?"
                taskArgs.append(projectID.uuidString)
            } else {
                taskSQL += " AND project_id IS NULL"
            }

            let taskRows = try Row.fetchAll(
                db,
                sql: taskSQL,
                arguments: StatementArguments(taskArgs)
            )
            let tasksByID: [UUID: Row] = Dictionary(
                uniqueKeysWithValues: taskRows.compactMap { row in
                    guard let idString = row["id"] as String?,
                          let id = UUID(uuidString: idString)
                    else { return nil }
                    return (id, row)
                }
            )

            // One dialogue query for all related tasks, then group in memory.
            let dialogueSQL = """
            SELECT e.task_id, e.kind, e.content, e.sequence
            FROM events e
            WHERE e.task_id IN (\(placeholders))
              AND (
                e.kind = ?
                OR (
                  e.kind = ?
                  AND NOT EXISTS (
                    SELECT 1 FROM event_tool_calls tc WHERE tc.event_id = e.id
                  )
                )
              )
            ORDER BY e.task_id, e.sequence DESC
            """
            var dialogueArgs: [any DatabaseValueConvertible] = ids.map(\.uuidString)
            dialogueArgs.append(AgentEventKind.userInput.rawValue)
            dialogueArgs.append(AgentEventKind.assistantResponse.rawValue)
            let dialogueRows = try Row.fetchAll(
                db,
                sql: dialogueSQL,
                arguments: StatementArguments(dialogueArgs)
            )

            var dialogueByTask: [UUID: [RelatedDialogueLine]] = [:]
            dialogueByTask.reserveCapacity(tasksByID.count)
            for row in dialogueRows {
                guard let taskIDString = row["task_id"] as String?,
                      let taskID = UUID(uuidString: taskIDString),
                      tasksByID[taskID] != nil,
                      let kindRaw = row["kind"] as String?,
                      let content = row["content"] as String?
                else { continue }
                let kind: RelatedDialogueLine.Kind
                switch kindRaw {
                case AgentEventKind.userInput.rawValue:
                    kind = .user
                case AgentEventKind.assistantResponse.rawValue:
                    kind = .assistant
                default:
                    continue
                }
                var lines = dialogueByTask[taskID] ?? []
                // Rows arrive newest-first per task; keep only the tail, then reverse later.
                if lines.count < Self.relatedDialogueLimit {
                    lines.append(RelatedDialogueLine(kind: kind, content: content))
                    dialogueByTask[taskID] = lines
                }
            }

            var snippets: [RelatedTaskContextSnippet] = []
            snippets.reserveCapacity(ids.count)
            for id in ids {
                guard let row = tasksByID[id] else { continue }
                let taskProjectID = (row["project_id"] as String?).flatMap(UUID.init(uuidString:))
                let recentDialogue = (dialogueByTask[id] ?? []).reversed()
                snippets.append(
                    RelatedTaskContextSnippet(
                        id: id,
                        projectID: taskProjectID,
                        topic: row["topic"],
                        summary: row["summary"],
                        abstract: row["abstract"],
                        recentDialogue: Array(recentDialogue)
                    )
                )
            }
            return snippets
        }
    }

    /// Tail size for related-context dialogue (user + plain assistant only).
    private static let relatedDialogueLimit = 4

    func updatePlanStep(
        taskID: UUID,
        stepID: UUID,
        status: StepStatus,
        result: String?
    ) throws {
        let pool = try database()
        try pool.write { db in
            try db.execute(
                sql: """
                UPDATE plan_steps
                SET status = ?, result = ?
                WHERE id = ?
                  AND plan_id IN (SELECT id FROM plans WHERE task_id = ?)
                """,
                arguments: [
                    status.rawValue,
                    result,
                    stepID.uuidString,
                    taskID.uuidString,
                ]
            )
            try db.execute(
                sql: "UPDATE tasks SET updated_at = ?, status = ? WHERE id = ?",
                arguments: [
                    Date.now.timeIntervalSince1970,
                    TaskStatus.active.rawValue,
                    taskID.uuidString,
                ]
            )
        }
    }

    func saveTaskState(_ task: TaskRecord, setActive: Bool) throws {
        let pool = try database()
        // `pool.write` already opens a transaction — do not nest `inTransaction`.
        try pool.write { db in
            try upsertTask(task, database: db)
            try replaceEntitiesIfNeeded(task.entities, taskID: task.id, database: db)
            try replaceRelations(task.relatedTaskIDs, taskID: task.id, database: db)
            try syncPendingPlan(task.pendingPlan, taskID: task.id, database: db)
            if setActive {
                try writeScopeActiveTask(
                    projectID: task.projectID,
                    taskID: task.id,
                    database: db
                )
            }
        }
    }

    func mutateTask(
        _ task: TaskRecord,
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        setActive: Bool
    ) throws {
        let pool = try database()
        try pool.write { db in
            try upsertTask(task, database: db)
            try replaceEntitiesIfNeeded(task.entities, taskID: task.id, database: db)
            try replaceRelations(task.relatedTaskIDs, taskID: task.id, database: db)
            try syncPendingPlan(task.pendingPlan, taskID: task.id, database: db)

            // Compute next sequence BEFORE deletions so we never reuse a
            // sequence value that was just freed (avoids UNIQUE constraint
            // violations when deleted events had the highest sequence).
            var nextSequence: Int?
            if !appendEvents.isEmpty {
                nextSequence = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COALESCE(MAX(sequence), -1) + 1
                    FROM events
                    WHERE task_id = ?
                    """,
                    arguments: [task.id.uuidString]
                ) ?? 0
            }

            for eventID in deleteEventIDs {
                try db.execute(
                    sql: "DELETE FROM events WHERE id = ? AND task_id = ?",
                    arguments: [eventID.uuidString, task.id.uuidString]
                )
            }

            if var sequence = nextSequence {
                for event in appendEvents {
                    try insertEvent(
                        event,
                        taskID: task.id,
                        sequence: sequence,
                        database: db
                    )
                    sequence += 1
                }
            }
            if setActive {
                try writeScopeActiveTask(
                    projectID: task.projectID,
                    taskID: task.id,
                    database: db
                )
            }
        }
    }

    func splitOffTurn(
        closingTask: TaskRecord,
        openingTask: TaskRecord,
        movedEventIDs: [UUID]
    ) throws {
        let pool = try database()
        try pool.write { db in
            try upsertTask(openingTask, database: db)
            try replaceEntitiesIfNeeded(openingTask.entities, taskID: openingTask.id, database: db)
            try replaceRelations(openingTask.relatedTaskIDs, taskID: openingTask.id, database: db)

            for (sequence, eventID) in movedEventIDs.enumerated() {
                try db.execute(
                    sql: """
                    UPDATE events SET task_id = ?, sequence = ?
                    WHERE id = ? AND task_id = ?
                    """,
                    arguments: [
                        openingTask.id.uuidString,
                        sequence,
                        eventID.uuidString,
                        closingTask.id.uuidString,
                    ]
                )
            }

            if openingTask.pendingPlan != nil {
                try db.execute(
                    sql: "UPDATE plans SET task_id = ? WHERE task_id = ?",
                    arguments: [openingTask.id.uuidString, closingTask.id.uuidString]
                )
            }

            let keepIDs = Set(closingTask.events.map(\.id.uuidString))
            if closingTask.events.isEmpty {
                try db.execute(
                    sql: "DELETE FROM tasks WHERE id = ?",
                    arguments: [closingTask.id.uuidString]
                )
            } else {
                let leftover = try String.fetchAll(
                    db,
                    sql: "SELECT id FROM events WHERE task_id = ?",
                    arguments: [closingTask.id.uuidString]
                ).filter { !keepIDs.contains($0) }
                for eventID in leftover {
                    try db.execute(
                        sql: "DELETE FROM events WHERE id = ? AND task_id = ?",
                        arguments: [eventID, closingTask.id.uuidString]
                    )
                }
                try upsertTask(closingTask, database: db)
                try replaceRelations(closingTask.relatedTaskIDs, taskID: closingTask.id, database: db)
                try syncPendingPlan(nil, taskID: closingTask.id, database: db)
            }

            try syncPendingPlan(openingTask.pendingPlan, taskID: openingTask.id, database: db)
            try writeScopeActiveTask(
                projectID: openingTask.projectID,
                taskID: openingTask.id,
                database: db
            )
        }
    }

    func rememberScopeActiveTask(projectID: UUID?, taskID: UUID) throws {
        let pool = try database()
        try pool.write { db in
            try writeScopeActiveTask(projectID: projectID, taskID: taskID, database: db)
        }
    }

    private func writeScopeActiveTask(
        projectID: UUID?,
        taskID: UUID,
        database db: Database
    ) throws {
        if let projectID {
            try db.execute(
                sql: """
                UPDATE projects
                SET last_active_task_id = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    taskID.uuidString,
                    Date.now.timeIntervalSince1970,
                    projectID.uuidString,
                ]
            )
        } else {
            let active = try String.fetchOne(
                db,
                sql: "SELECT active_task_id FROM app_state WHERE singleton = 1"
            )
            let focused = try String.fetchOne(
                db,
                sql: "SELECT focused_project_id FROM app_state WHERE singleton = 1"
            )
            try db.execute(
                sql: """
                INSERT INTO app_state (
                    singleton, active_task_id, focused_project_id, last_general_task_id
                ) VALUES (1, ?, ?, ?)
                ON CONFLICT(singleton) DO UPDATE SET
                    last_general_task_id = excluded.last_general_task_id
                """,
                arguments: [active, focused, taskID.uuidString]
            )
        }
    }

    // MARK: - Database

    func database() throws -> DatabasePool {
        if let databasePool {
            return databasePool
        }

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let pool = try DatabasePool(
            path: databaseURL.path,
            configuration: configuration
        )
        var migrator = DatabaseMigrator()
        GRDBTaskSchema.registerMigrations(&migrator)
        try migrator.migrate(pool)
        try importLegacyJSONIfNeeded(into: pool)
        databasePool = pool
        return pool
    }

    // MARK: - Writes

    func updateTopic(
        taskID: UUID,
        topic: String,
        abstract: String,
        topicUpdatedAt: Date
    ) throws {
        let pool = try database()
        try pool.write { db in
            try db.execute(
                sql: """
                UPDATE tasks
                SET topic = ?,
                    abstract = ?,
                    topic_updated_at = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    topic,
                    abstract,
                    topicUpdatedAt.timeIntervalSince1970,
                    topicUpdatedAt.timeIntervalSince1970,
                    taskID.uuidString,
                ]
            )
        }
    }

    func deleteTask(id: UUID) throws {
        let pool = try database()
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

}
