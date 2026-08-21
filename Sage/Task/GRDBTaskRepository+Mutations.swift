//
//  GRDBTaskRepository+Mutations.swift
//  Sage
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    func saveTaskState(_ task: TaskRecord, setActive: Bool) throws {
        let pool = try database()
        // `pool.write` already opens a transaction — do not nest `inTransaction`.
        try pool.write { database in
            try upsertTask(task, database: database)
            try replaceEntitiesIfNeeded(task.entities, taskID: task.id, database: database)
            try replaceRelations(task.relatedTaskIDs, taskID: task.id, database: database)
            try syncPendingPlan(task.pendingPlan, taskID: task.id, database: database)
            if setActive {
                try writeScopeActiveTask(
                    projectID: task.projectID,
                    taskID: task.id,
                    database: database
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
        try pool.write { database in
            try upsertTask(task, database: database)
            try replaceEntitiesIfNeeded(task.entities, taskID: task.id, database: database)
            try replaceRelations(task.relatedTaskIDs, taskID: task.id, database: database)
            try syncPendingPlan(task.pendingPlan, taskID: task.id, database: database)

            // Compute next sequence BEFORE deletions so we never reuse a
            // sequence value that was just freed (avoids UNIQUE constraint
            // violations when deleted events had the highest sequence).
            var nextSequence: Int?
            if !appendEvents.isEmpty {
                nextSequence = try Int.fetchOne(
                    database,
                    sql: """
                    SELECT COALESCE(MAX(sequence), -1) + 1
                    FROM events
                    WHERE task_id = ?
                    """,
                    arguments: [task.id.uuidString]
                ) ?? 0
            }

            for eventID in deleteEventIDs {
                try database.execute(
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
                        database: database
                    )
                    sequence += 1
                }
            }
            if setActive {
                try writeScopeActiveTask(
                    projectID: task.projectID,
                    taskID: task.id,
                    database: database
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
        try pool.write { database in
            try upsertTask(openingTask, database: database)
            try replaceEntitiesIfNeeded(openingTask.entities, taskID: openingTask.id, database: database)
            try replaceRelations(openingTask.relatedTaskIDs, taskID: openingTask.id, database: database)

            for (sequence, eventID) in movedEventIDs.enumerated() {
                try database.execute(
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

            try reassignPendingPlanIfNeeded(
                openingTask: openingTask,
                closingTask: closingTask,
                database: database
            )
            try settleClosingTaskAfterSplit(closingTask, database: database)

            try syncPendingPlan(openingTask.pendingPlan, taskID: openingTask.id, database: database)
            try writeScopeActiveTask(
                projectID: openingTask.projectID,
                taskID: openingTask.id,
                database: database
            )
        }
    }

    func reassignPendingPlanIfNeeded(
        openingTask: TaskRecord,
        closingTask: TaskRecord,
        database: Database
    ) throws {
        guard openingTask.pendingPlan != nil else { return }
        try database.execute(
            sql: "UPDATE plans SET task_id = ? WHERE task_id = ?",
            arguments: [openingTask.id.uuidString, closingTask.id.uuidString]
        )
    }

    func settleClosingTaskAfterSplit(_ closingTask: TaskRecord, database: Database) throws {
        let keepIDs = Set(closingTask.events.map(\.id.uuidString))
        if closingTask.events.isEmpty {
            try database.execute(
                sql: "DELETE FROM tasks WHERE id = ?",
                arguments: [closingTask.id.uuidString]
            )
            return
        }
        let leftover = try String.fetchAll(
            database,
            sql: "SELECT id FROM events WHERE task_id = ?",
            arguments: [closingTask.id.uuidString]
        )
        .filter { !keepIDs.contains($0) }
        for eventID in leftover {
            try database.execute(
                sql: "DELETE FROM events WHERE id = ? AND task_id = ?",
                arguments: [eventID, closingTask.id.uuidString]
            )
        }
        try upsertTask(closingTask, database: database)
        try replaceRelations(closingTask.relatedTaskIDs, taskID: closingTask.id, database: database)
        try syncPendingPlan(nil, taskID: closingTask.id, database: database)
    }

    func rememberScopeActiveTask(projectID: UUID?, taskID: UUID) throws {
        let pool = try database()
        try pool.write { database in
            try writeScopeActiveTask(projectID: projectID, taskID: taskID, database: database)
        }
    }

    func writeScopeActiveTask(
        projectID: UUID?,
        taskID: UUID,
        database: Database
    ) throws {
        if let projectID {
            try database.execute(
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
                database,
                sql: "SELECT active_task_id FROM app_state WHERE singleton = 1"
            )
            let focused = try String.fetchOne(
                database,
                sql: "SELECT focused_project_id FROM app_state WHERE singleton = 1"
            )
            try database.execute(
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
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
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
}
