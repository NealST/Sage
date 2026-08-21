//
//  GRDBTaskRepository+Projects.swift
//  Sage
//
//  Project open/create, focus pointers, and erase.
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    func setFocus(projectID: UUID?, activeTaskID: UUID?) throws {
        let pool = try database()
        try pool.write { database in
            if let activeTaskID {
                guard let row = try Row.fetchOne(
                    database,
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
                database: database
            )
        }
    }

    func openProject(rootURL: URL, displayName: String?) throws -> ProjectRecord {
        let validated = try PathGuard.validateProjectRoot(rootURL)
        try ProjectSageLayout.ensureLayout(at: validated)
        let pool = try database()
        return try pool.write { database in
            if let existing = try loadProject(rootPath: validated.path, database: database) {
                var updated = existing
                updated.lastOpenedAt = .now
                updated.updatedAt = .now
                if let displayName, !displayName.isEmpty {
                    updated.name = displayName
                }
                try upsertProject(updated, database: database)
                return updated
            }
            let name = displayName?.nilIfEmpty ?? validated.lastPathComponent
            let project = ProjectRecord(name: name, rootPath: validated.path)
            try upsertProject(project, database: database)
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
        try pool.write { database in
            try database.execute(
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
        try pool.write { database in
            // Ensure app_state row exists; preserve other focus columns.
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
                arguments: [active, focused, taskID?.uuidString]
            )
        }
    }

    func lastGeneralTaskID() throws -> UUID? {
        let pool = try database()
        return try pool.read { database in
            let raw = try String.fetchOne(
                database,
                sql: "SELECT last_general_task_id FROM app_state WHERE singleton = 1"
            )
            return raw.flatMap(UUID.init(uuidString:))
        }
    }

    func eraseAllData() throws {
        let pool = try database()
        try pool.write { database in
            try database.execute(sql: "UPDATE projects SET last_active_task_id = NULL")
            try database.execute(sql: "DELETE FROM event_context_tasks")
            try database.execute(sql: "DELETE FROM event_contexts")
            try database.execute(sql: "DELETE FROM event_tool_calls")
            try database.execute(sql: "DELETE FROM plan_steps")
            try database.execute(sql: "DELETE FROM plans")
            try database.execute(sql: "DELETE FROM task_relations")
            try database.execute(sql: "DELETE FROM task_entities")
            try database.execute(sql: "DELETE FROM events")
            try database.execute(sql: "DELETE FROM app_state")
            try database.execute(sql: "DELETE FROM schedule_runs")
            try database.execute(sql: "DELETE FROM schedules")
            try database.execute(sql: "DELETE FROM tasks")
            try database.execute(sql: "DELETE FROM projects")
        }
        try? FileManager.default.removeItem(at: legacyJSONURL)
    }

    private func writeFocus(
        projectID: UUID?,
        activeTaskID: UUID?,
        database: Database
    ) throws {
        let lastGeneral = try String.fetchOne(
            database,
            sql: "SELECT last_general_task_id FROM app_state WHERE singleton = 1"
        )
        try database.execute(
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
}
