//
//  GRDBTaskRepository+LegacyImport.swift
//  Sage
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    func importLegacyJSONIfNeeded(into pool: DatabasePool) throws {
        guard
            let data = try? Data(contentsOf: legacyJSONURL),
            let snapshot = try? JSONDecoder().decode(TaskLibrarySnapshot.self, from: data)
        else {
            return
        }

        let didImport = try pool.write { database in
            let existingCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM tasks"
            ) ?? 0
            guard existingCount == 0 else { return false }

            // Insert every task first so relation foreign keys are valid.
            for task in snapshot.tasks {
                try upsertTask(task, database: database)
            }
            for task in snapshot.tasks {
                try replaceEntitiesIfNeeded(task.entities, taskID: task.id, database: database)
                try replaceRelations(task.relatedTaskIDs, taskID: task.id, database: database)
                try syncPendingPlan(task.pendingPlan, taskID: task.id, database: database)
                for (sequence, event) in task.events.enumerated() {
                    try insertEvent(
                        event,
                        taskID: task.id,
                        sequence: sequence,
                        database: database
                    )
                }
            }
            try database.execute(
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
}
