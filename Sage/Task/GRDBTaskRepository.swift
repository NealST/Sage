//
//  GRDBTaskRepository.swift
//  Sage
//

import Foundation
import GRDB

actor GRDBTaskRepository: TaskRepository {
    private let databaseURL: URL
    private let legacyJSONURL: URL
    private var databasePool: DatabasePool?

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = appSupport.appendingPathComponent("Sage", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        databaseURL = directory.appendingPathComponent("sage.sqlite")
        legacyJSONURL = directory.appendingPathComponent("tasks.json")
    }

    func loadWorkspace() throws -> TaskWorkspaceSnapshot {
        let pool = try database()
        return try pool.read { db in
            let focusRow = try Row.fetchOne(
                db,
                sql: "SELECT active_task_id, focused_project_id FROM app_state WHERE singleton = 1"
            )
            let activeTaskID = (focusRow?["active_task_id"] as String?)
                .flatMap(UUID.init(uuidString:))
            let focusedProjectID = (focusRow?["focused_project_id"] as String?)
                .flatMap(UUID.init(uuidString:))

            let focusedProject: ProjectRecord?
            if let focusedProjectID {
                focusedProject = try loadProject(id: focusedProjectID, database: db)
            } else {
                focusedProject = nil
            }

            let summaryRows: [Row]
            if let focusedProjectID {
                summaryRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, status, project_id, summary, topic, abstract, updated_at
                    FROM tasks
                    WHERE project_id = ?
                    ORDER BY updated_at DESC
                    LIMIT 40
                    """,
                    arguments: [focusedProjectID.uuidString]
                )
            } else {
                summaryRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, status, project_id, summary, topic, abstract, updated_at
                    FROM tasks
                    WHERE project_id IS NULL
                    ORDER BY updated_at DESC
                    LIMIT 40
                    """
                )
            }

            let recentSummaries = summaryRows.compactMap { row -> TaskSummary? in
                Self.taskSummary(from: row)
            }

            let recentProjects = try loadRecentProjects(limit: 12, database: db)

            let activeTask: TaskRecord?
            if let activeTaskID,
               let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tasks WHERE id = ?",
                arguments: [activeTaskID.uuidString]
               ),
               let loaded = try loadTask(from: row, database: db),
               loaded.projectID == focusedProjectID {
                activeTask = loaded
            } else if let first = recentSummaries.first,
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
                activeTaskID: activeTask?.id ?? activeTaskID
            )
        }
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
            return try loadTask(from: row, database: db)
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

    func saveTaskState(_ task: TaskRecord, setActive: Bool) throws {
        let pool = try database()
        // `pool.write` already opens a transaction — do not nest `inTransaction`.
        try pool.write { db in
            try upsertTask(task, database: db)
            try replaceEntitiesIfNeeded(task.entities, taskID: task.id, database: db)
            try replaceRelations(task.relatedTaskIDs, taskID: task.id, database: db)
            try replacePendingPlan(task.pendingPlan, taskID: task.id, database: db)
            if setActive {
                try writeActiveTaskID(task.id, database: db)
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
            try replacePendingPlan(task.pendingPlan, taskID: task.id, database: db)

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
                try writeActiveTaskID(task.id, database: db)
            }
        }
    }

    func setFocus(projectID: UUID?, activeTaskID: UUID?) throws {
        let pool = try database()
        try pool.write { db in
            if let activeTaskID {
                guard let row = try Row.fetchOne(
                    db,
                    sql: "SELECT project_id FROM tasks WHERE id = ?",
                    arguments: [activeTaskID.uuidString]
                ) else {
                    throw ToolError.operationFailed("Active task not found.")
                }
                let taskProjectID = (row["project_id"] as String?).flatMap(UUID.init(uuidString:))
                guard taskProjectID == projectID else {
                    throw ToolError.operationFailed(
                        "Active task does not belong to the focused project."
                    )
                }
            }
            try writeFocus(
                projectID: projectID,
                activeTaskID: activeTaskID,
                database: db
            )
        }
    }

    func openProject(rootURL: URL, displayName: String?) throws -> ProjectRecord {
        let validated = try PathGuard.validateProjectRoot(rootURL)
        let pool = try database()
        return try pool.write { db in
            if let existing = try loadProject(rootPath: validated.path, database: db) {
                var updated = existing
                updated.lastOpenedAt = .now
                updated.updatedAt = .now
                if let displayName, !displayName.isEmpty {
                    updated.name = displayName
                }
                try upsertProject(updated, database: db)
                return updated
            }
            let name = displayName?.nilIfEmpty ?? validated.lastPathComponent
            let project = ProjectRecord(name: name, rootPath: validated.path)
            try upsertProject(project, database: db)
            return project
        }
    }

    func createProject(parentURL: URL, name: String, gitInit: Bool) throws -> ProjectRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.invalidArguments("Project name cannot be empty.")
        }
        guard !trimmed.contains("/") else {
            throw ToolError.invalidArguments("Project name cannot contain '/'.")
        }
        let parent = try PathGuard.validateProjectRoot(parentURL)
        let root = parent.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: root.path) {
            throw ToolError.operationFailed(
                "Path already exists: \(root.path). Open it instead, or choose another name."
            )
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        if gitInit {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "init"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
        return try openProject(rootURL: root, displayName: trimmed)
    }

    func setProjectLastActiveTask(projectID: UUID, taskID: UUID?) throws {
        let pool = try database()
        try pool.write { db in
            try db.execute(
                sql: """
                UPDATE projects
                SET last_active_task_id = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    taskID?.uuidString,
                    Date.now.timeIntervalSince1970,
                    projectID.uuidString,
                ]
            )
        }
    }

    func setLastGeneralTaskID(_ taskID: UUID?) throws {
        let pool = try database()
        try pool.write { db in
            // Ensure app_state row exists; preserve other focus columns.
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
                arguments: [active, focused, taskID?.uuidString]
            )
        }
    }

    func lastGeneralTaskID() throws -> UUID? {
        let pool = try database()
        return try pool.read { db in
            let raw = try String.fetchOne(
                db,
                sql: "SELECT last_general_task_id FROM app_state WHERE singleton = 1"
            )
            return raw.flatMap(UUID.init(uuidString:))
        }
    }

    func eraseAllData() throws {
        let pool = try database()
        try pool.write { db in
            try db.execute(sql: "UPDATE projects SET last_active_task_id = NULL")
            try db.execute(sql: "DELETE FROM event_context_tasks")
            try db.execute(sql: "DELETE FROM event_contexts")
            try db.execute(sql: "DELETE FROM event_tool_calls")
            try db.execute(sql: "DELETE FROM plan_steps")
            try db.execute(sql: "DELETE FROM plans")
            try db.execute(sql: "DELETE FROM task_relations")
            try db.execute(sql: "DELETE FROM task_entities")
            try db.execute(sql: "DELETE FROM events")
            try db.execute(sql: "DELETE FROM app_state")
            try db.execute(sql: "DELETE FROM tasks")
            try db.execute(sql: "DELETE FROM projects")
        }
        try? FileManager.default.removeItem(at: legacyJSONURL)
    }

    private func writeFocus(
        projectID: UUID?,
        activeTaskID: UUID?,
        database db: Database
    ) throws {
        let lastGeneral = try String.fetchOne(
            db,
            sql: "SELECT last_general_task_id FROM app_state WHERE singleton = 1"
        )
        try db.execute(
            sql: """
            INSERT INTO app_state (
                singleton, active_task_id, focused_project_id, last_general_task_id
            )
            VALUES (1, ?, ?, ?)
            ON CONFLICT(singleton) DO UPDATE SET
                active_task_id = excluded.active_task_id,
                focused_project_id = excluded.focused_project_id
            """,
            arguments: [activeTaskID?.uuidString, projectID?.uuidString, lastGeneral]
        )
    }

    private func writeActiveTaskID(_ taskID: UUID?, database db: Database) throws {
        // Preserve focused_project_id / last_general_task_id when only flipping active task.
        let focused = try String.fetchOne(
            db,
            sql: "SELECT focused_project_id FROM app_state WHERE singleton = 1"
        )
        let lastGeneral = try String.fetchOne(
            db,
            sql: "SELECT last_general_task_id FROM app_state WHERE singleton = 1"
        )
        try db.execute(
            sql: """
            INSERT INTO app_state (
                singleton, active_task_id, focused_project_id, last_general_task_id
            )
            VALUES (1, ?, ?, ?)
            ON CONFLICT(singleton) DO UPDATE SET
                active_task_id = excluded.active_task_id,
                focused_project_id = COALESCE(excluded.focused_project_id, app_state.focused_project_id)
            """,
            arguments: [taskID?.uuidString, focused, lastGeneral]
        )
    }

    // MARK: - Database

    private func database() throws -> DatabasePool {
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
        migrator.registerMigration("createTaskStore") { db in
            try db.execute(sql: Self.schemaSQL)
        }
        migrator.registerMigration("addTopicFields") { db in
            try db.execute(sql: """
                ALTER TABLE tasks ADD COLUMN topic TEXT;
                ALTER TABLE tasks ADD COLUMN abstract TEXT;
                ALTER TABLE tasks ADD COLUMN topic_updated_at REAL;
            """)
        }
        migrator.registerMigration("addProjects") { db in
            try db.execute(sql: """
                CREATE TABLE projects (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    root_path TEXT NOT NULL UNIQUE,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    last_opened_at REAL NOT NULL,
                    last_active_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL
                );

                CREATE INDEX projects_last_opened
                ON projects(last_opened_at DESC);

                ALTER TABLE tasks ADD COLUMN project_id TEXT REFERENCES projects(id) ON DELETE SET NULL;

                CREATE INDEX tasks_project_updated
                ON tasks(project_id, updated_at DESC);

                ALTER TABLE app_state ADD COLUMN focused_project_id TEXT REFERENCES projects(id) ON DELETE SET NULL;
            """)
        }
        migrator.registerMigration("addLastGeneralTask") { db in
            try db.execute(sql: """
                ALTER TABLE app_state ADD COLUMN last_general_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL;
            """)
        }
        try migrator.migrate(pool)
        try importLegacyJSONIfNeeded(into: pool)
        databasePool = pool
        return pool
    }

    private nonisolated static let schemaSQL = """
    CREATE TABLE tasks (
        id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL,
        summary TEXT,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE INDEX tasks_updated_at
    ON tasks(updated_at DESC);

    CREATE TABLE app_state (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        active_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL
    );

    CREATE TABLE events (
        id TEXT PRIMARY KEY NOT NULL,
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        sequence INTEGER NOT NULL,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        tool_call_id TEXT,
        created_at REAL NOT NULL,
        UNIQUE(task_id, sequence)
    );

    CREATE INDEX events_task_sequence
    ON events(task_id, sequence);

    CREATE TABLE event_tool_calls (
        event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        call_id TEXT NOT NULL,
        name TEXT NOT NULL,
        arguments_json TEXT NOT NULL,
        PRIMARY KEY(event_id, position)
    );

    CREATE TABLE event_contexts (
        event_id TEXT PRIMARY KEY NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        confidence REAL NOT NULL,
        reason TEXT NOT NULL
    );

    CREATE TABLE event_context_tasks (
        event_id TEXT NOT NULL REFERENCES event_contexts(event_id) ON DELETE CASCADE,
        related_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        PRIMARY KEY(event_id, related_task_id)
    );

    CREATE TABLE task_entities (
        id TEXT PRIMARY KEY NOT NULL,
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        value TEXT NOT NULL,
        UNIQUE(task_id, kind, value)
    );

    CREATE INDEX task_entities_lookup
    ON task_entities(kind, value);

    CREATE TABLE task_relations (
        source_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        target_task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        PRIMARY KEY(source_task_id, target_task_id)
    );

    CREATE TABLE plans (
        id TEXT PRIMARY KEY NOT NULL,
        task_id TEXT UNIQUE NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        summary TEXT NOT NULL
    );

    CREATE TABLE plan_steps (
        id TEXT PRIMARY KEY NOT NULL,
        plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        tool_call_id TEXT NOT NULL,
        tool_name TEXT NOT NULL,
        arguments_json TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        result TEXT,
        UNIQUE(plan_id, position)
    );
    """

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

    private func upsertTask(_ task: TaskRecord, database db: Database) throws {
        // COALESCE keeps an existing topic when a concurrent in-memory snapshot
        // still has nil (topic generation racing with commit/mutate).
        try db.execute(
            sql: """
            INSERT INTO tasks (
                id, status, project_id, summary, topic, abstract,
                topic_updated_at, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                status = excluded.status,
                project_id = excluded.project_id,
                summary = excluded.summary,
                topic = COALESCE(excluded.topic, tasks.topic),
                abstract = COALESCE(excluded.abstract, tasks.abstract),
                topic_updated_at = COALESCE(excluded.topic_updated_at, tasks.topic_updated_at),
                updated_at = excluded.updated_at
            """,
            arguments: [
                task.id.uuidString,
                task.status.rawValue,
                task.projectID?.uuidString,
                task.summary,
                task.topic,
                task.abstract,
                task.topicUpdatedAt?.timeIntervalSince1970,
                task.createdAt.timeIntervalSince1970,
                task.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    /// Entity extraction is not wired yet — skip the DELETE when the in-memory
    /// list is empty (the common hot path) so every commit doesn't touch the table.
    private func replaceEntitiesIfNeeded(
        _ entities: [TaskEntity],
        taskID: UUID,
        database db: Database
    ) throws {
        guard !entities.isEmpty else { return }
        try db.execute(
            sql: "DELETE FROM task_entities WHERE task_id = ?",
            arguments: [taskID.uuidString]
        )
        for entity in entities {
            try db.execute(
                sql: """
                INSERT INTO task_entities (id, task_id, kind, value)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    entity.id.uuidString,
                    taskID.uuidString,
                    entity.kind,
                    entity.value,
                ]
            )
        }
    }

    private func replaceRelations(
        _ relatedTaskIDs: [UUID],
        taskID: UUID,
        database db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM task_relations WHERE source_task_id = ?",
            arguments: [taskID.uuidString]
        )
        for (position, relatedID) in relatedTaskIDs.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO task_relations (
                    source_task_id, target_task_id, position
                ) VALUES (?, ?, ?)
                """,
                arguments: [
                    taskID.uuidString,
                    relatedID.uuidString,
                    position,
                ]
            )
        }
    }

    private func replacePendingPlan(
        _ plan: AgentPlan?,
        taskID: UUID,
        database db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM plans WHERE task_id = ?",
            arguments: [taskID.uuidString]
        )
        guard let plan else { return }

        try db.execute(
            sql: "INSERT INTO plans (id, task_id, summary) VALUES (?, ?, ?)",
            arguments: [
                plan.id.uuidString,
                taskID.uuidString,
                plan.summary,
            ]
        )
        for (position, step) in plan.steps.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO plan_steps (
                    id, plan_id, position, tool_call_id, tool_name,
                    arguments_json, title, status, result
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    step.id.uuidString,
                    plan.id.uuidString,
                    position,
                    step.toolCallID,
                    step.toolName,
                    step.argumentsJSON,
                    step.title,
                    step.status.rawValue,
                    step.result,
                ]
            )
        }
    }

    private func insertEvent(
        _ event: AgentEvent,
        taskID: UUID,
        sequence: Int,
        database db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO events (
                id, task_id, sequence, kind, content, tool_call_id, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                event.id.uuidString,
                taskID.uuidString,
                sequence,
                event.kind.rawValue,
                event.content,
                event.toolCallID,
                event.createdAt.timeIntervalSince1970,
            ]
        )

        for (position, call) in (event.toolCalls ?? []).enumerated() {
            try db.execute(
                sql: """
                INSERT INTO event_tool_calls (
                    event_id, position, call_id, name, arguments_json
                ) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString,
                    position,
                    call.id,
                    call.name,
                    call.argumentsJSON,
                ]
            )
        }

        if let context = event.context {
            try db.execute(
                sql: """
                INSERT INTO event_contexts (event_id, confidence, reason)
                VALUES (?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString,
                    context.confidence,
                    context.reason,
                ]
            )
            for (position, relatedID) in context.relatedTaskIDs.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO event_context_tasks (
                        event_id, related_task_id, position
                    ) VALUES (?, ?, ?)
                    """,
                    arguments: [
                        event.id.uuidString,
                        relatedID.uuidString,
                        position,
                    ]
                )
            }
        }
    }

    /// Imports the short-lived JSON prototype once, then removes it.
    private func importLegacyJSONIfNeeded(into pool: DatabasePool) throws {
        guard
            let data = try? Data(contentsOf: legacyJSONURL),
            let snapshot = try? JSONDecoder().decode(TaskLibrarySnapshot.self, from: data)
        else {
            return
        }

        let didImport = try pool.write { db in
            let existingCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM tasks"
            ) ?? 0
            guard existingCount == 0 else { return false }

            // Insert every task first so relation foreign keys are valid.
            for task in snapshot.tasks {
                try upsertTask(task, database: db)
            }
            for task in snapshot.tasks {
                try replaceEntitiesIfNeeded(task.entities, taskID: task.id, database: db)
                try replaceRelations(task.relatedTaskIDs, taskID: task.id, database: db)
                try replacePendingPlan(task.pendingPlan, taskID: task.id, database: db)
                for (sequence, event) in task.events.enumerated() {
                    try insertEvent(
                        event,
                        taskID: task.id,
                        sequence: sequence,
                        database: db
                    )
                }
            }
            try db.execute(
                sql: """
                INSERT INTO app_state (singleton, active_task_id, focused_project_id)
                VALUES (1, ?, NULL)
                ON CONFLICT(singleton) DO UPDATE
                SET active_task_id = excluded.active_task_id
                """,
                arguments: [snapshot.activeTaskID?.uuidString]
            )
            return true
        }

        // Always remove legacy JSON after an import attempt so it cannot resurrect history.
        if didImport || FileManager.default.fileExists(atPath: legacyJSONURL.path) {
            try? FileManager.default.removeItem(at: legacyJSONURL)
        }
    }

    // MARK: - Reads

    private func loadTask(from row: Row, database db: Database) throws -> TaskRecord? {
        guard
            let id = UUID(uuidString: row["id"]),
            let status = TaskStatus(rawValue: row["status"])
        else {
            return nil
        }

        let topicUpdatedAt: Date? = (row["topic_updated_at"] as Double?)
            .map { Date(timeIntervalSince1970: $0) }

        let projectID = (row["project_id"] as String?).flatMap(UUID.init(uuidString:))

        return TaskRecord(
            id: id,
            status: status,
            projectID: projectID,
            summary: row["summary"],
            topic: row["topic"],
            abstract: row["abstract"],
            topicUpdatedAt: topicUpdatedAt,
            events: try loadEvents(taskID: id, database: db),
            pendingPlan: try loadPlan(taskID: id, database: db),
            // Entity extraction is not wired; skip the table read on the hot path.
            entities: [],
            relatedTaskIDs: try loadRelations(taskID: id, database: db),
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }

    private func loadProject(id: UUID, database db: Database) throws -> ProjectRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM projects WHERE id = ?",
            arguments: [id.uuidString]
        ) else { return nil }
        return Self.projectRecord(from: row)
    }

    private func loadProject(rootPath: String, database db: Database) throws -> ProjectRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM projects WHERE root_path = ?",
            arguments: [rootPath]
        ) else { return nil }
        return Self.projectRecord(from: row)
    }

    private func loadRecentProjects(limit: Int, database db: Database) throws -> [ProjectRecord] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM projects
            ORDER BY last_opened_at DESC
            LIMIT ?
            """,
            arguments: [limit]
        )
        return rows.compactMap(Self.projectRecord(from:))
    }

    private func upsertProject(_ project: ProjectRecord, database db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO projects (
                id, name, root_path, created_at, updated_at,
                last_opened_at, last_active_task_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                root_path = excluded.root_path,
                updated_at = excluded.updated_at,
                last_opened_at = excluded.last_opened_at,
                last_active_task_id = excluded.last_active_task_id
            """,
            arguments: [
                project.id.uuidString,
                project.name,
                project.rootPath,
                project.createdAt.timeIntervalSince1970,
                project.updatedAt.timeIntervalSince1970,
                project.lastOpenedAt.timeIntervalSince1970,
                project.lastActiveTaskID?.uuidString,
            ]
        )
    }

    private static func projectRecord(from row: Row) -> ProjectRecord? {
        guard let id = UUID(uuidString: row["id"]) else { return nil }
        return ProjectRecord(
            id: id,
            name: row["name"],
            rootPath: row["root_path"],
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
            lastOpenedAt: Date(timeIntervalSince1970: row["last_opened_at"]),
            lastActiveTaskID: (row["last_active_task_id"] as String?)
                .flatMap(UUID.init(uuidString:))
        )
    }

    private static func taskSummary(from row: Row) -> TaskSummary? {
        guard
            let id = UUID(uuidString: row["id"]),
            let status = TaskStatus(rawValue: row["status"])
        else { return nil }
        return TaskSummary(
            id: id,
            status: status,
            projectID: (row["project_id"] as String?).flatMap(UUID.init(uuidString:)),
            summary: row["summary"],
            topic: row["topic"],
            abstract: row["abstract"],
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }

    private func loadEvents(taskID: UUID, database db: Database) throws -> [AgentEvent] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM events
            WHERE task_id = ?
            ORDER BY sequence
            """,
            arguments: [taskID.uuidString]
        )
        guard !rows.isEmpty else { return [] }

        let eventIDStrings: [String] = rows.compactMap { row in
            guard let id = row["id"] as String? else { return nil }
            return id
        }
        let toolCallsByEvent = try loadToolCalls(forEventIDs: eventIDStrings, database: db)
        let contextsByEvent = try loadContexts(forEventIDs: eventIDStrings, database: db)

        return rows.compactMap { row in
            guard
                let idString = row["id"] as String?,
                let id = UUID(uuidString: idString),
                let kind = AgentEventKind(rawValue: row["kind"])
            else {
                return nil
            }
            let toolCalls = toolCallsByEvent[idString] ?? []
            return AgentEvent(
                id: id,
                kind: kind,
                content: row["content"],
                toolCallID: row["tool_call_id"],
                toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                context: contextsByEvent[idString],
                createdAt: Date(timeIntervalSince1970: row["created_at"])
            )
        }
    }

    private func loadToolCalls(
        forEventIDs eventIDs: [String],
        database db: Database
    ) throws -> [String: [ToolCallRecord]] {
        guard !eventIDs.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: eventIDs.count).joined(separator: ", ")
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT event_id, call_id, name, arguments_json
            FROM event_tool_calls
            WHERE event_id IN (\(placeholders))
            ORDER BY event_id, position
            """,
            arguments: StatementArguments(eventIDs)
        )
        var result: [String: [ToolCallRecord]] = [:]
        for row in rows {
            let eventID: String = row["event_id"]
            result[eventID, default: []].append(
                ToolCallRecord(
                    id: row["call_id"],
                    name: row["name"],
                    argumentsJSON: row["arguments_json"]
                )
            )
        }
        return result
    }

    private func loadContexts(
        forEventIDs eventIDs: [String],
        database db: Database
    ) throws -> [String: EventContext] {
        guard !eventIDs.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: eventIDs.count).joined(separator: ", ")
        let contextRows = try Row.fetchAll(
            db,
            sql: """
            SELECT event_id, confidence, reason
            FROM event_contexts
            WHERE event_id IN (\(placeholders))
            """,
            arguments: StatementArguments(eventIDs)
        )
        guard !contextRows.isEmpty else { return [:] }

        let relatedRows = try Row.fetchAll(
            db,
            sql: """
            SELECT event_id, related_task_id
            FROM event_context_tasks
            WHERE event_id IN (\(placeholders))
            ORDER BY event_id, position
            """,
            arguments: StatementArguments(eventIDs)
        )
        var relatedByEvent: [String: [UUID]] = [:]
        for row in relatedRows {
            let eventID: String = row["event_id"]
            if let related = UUID(uuidString: row["related_task_id"]) {
                relatedByEvent[eventID, default: []].append(related)
            }
        }

        var result: [String: EventContext] = [:]
        for row in contextRows {
            let eventID: String = row["event_id"]
            result[eventID] = EventContext(
                relatedTaskIDs: relatedByEvent[eventID] ?? [],
                confidence: row["confidence"],
                reason: row["reason"]
            )
        }
        return result
    }

    private func loadRelations(taskID: UUID, database db: Database) throws -> [UUID] {
        try String.fetchAll(
            db,
            sql: """
            SELECT target_task_id FROM task_relations
            WHERE source_task_id = ?
            ORDER BY position
            """,
            arguments: [taskID.uuidString]
        ).compactMap(UUID.init(uuidString:))
    }

    private func loadPlan(taskID: UUID, database db: Database) throws -> AgentPlan? {
        guard let planRow = try Row.fetchOne(
            db,
            sql: "SELECT * FROM plans WHERE task_id = ?",
            arguments: [taskID.uuidString]
        ), let planID = UUID(uuidString: planRow["id"]) else {
            return nil
        }
        let stepRows = try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM plan_steps
            WHERE plan_id = ?
            ORDER BY position
            """,
            arguments: [planID.uuidString]
        )
        let steps = stepRows.compactMap { row -> AgentStep? in
            guard
                let id = UUID(uuidString: row["id"]),
                let status = StepStatus(rawValue: row["status"])
            else {
                return nil
            }
            return AgentStep(
                id: id,
                toolCallID: row["tool_call_id"],
                toolName: row["tool_name"],
                argumentsJSON: row["arguments_json"],
                title: row["title"],
                status: status,
                result: row["result"]
            )
        }
        return AgentPlan(
            id: planID,
            summary: planRow["summary"],
            steps: steps
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
