//
//  GRDBTaskRepository+Queries.swift
//  Sage
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    func loadProject(id: UUID) throws -> ProjectRecord? {
        let pool = try database()
        return try pool.read { database in
            try loadProject(id: id, database: database)
        }
    }

    func listRecentProjects(limit: Int) throws -> [ProjectRecord] {
        let pool = try database()
        return try pool.read { database in
            try loadRecentProjects(limit: limit, database: database)
        }
    }

    func loadTask(id: UUID) throws -> TaskRecord? {
        let pool = try database()
        return try pool.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try loadTask(from: row, database: database, includeHistory: true)
        }
    }

    func loadTaskMetadata(id: UUID) throws -> TaskRecord? {
        let pool = try database()
        return try pool.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM tasks WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try loadTask(from: row, database: database, includeHistory: false)
        }
    }

    func hasPendingPlan(taskID: UUID) throws -> Bool {
        let pool = try database()
        return try pool.read { database in
            try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS (SELECT 1 FROM plans WHERE task_id = ?)",
                arguments: [taskID.uuidString]
            ) ?? false
        }
    }

    func filterTaskIDs(_ ids: [UUID], projectID: UUID?) throws -> [UUID] {
        guard !ids.isEmpty else { return [] }
        let pool = try database()
        return try pool.read { database in
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
            let found = try String.fetchAll(database, sql: sql, arguments: StatementArguments(arguments))
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
        return try pool.read { database in
            let tasksByID = try loadRelatedTaskRows(ids: ids, projectID: projectID, database: database)
            let dialogueByTask = try loadRelatedDialogue(
                ids: ids,
                tasksByID: tasksByID,
                database: database
            )
            return assembleRelatedSnippets(ids: ids, tasksByID: tasksByID, dialogueByTask: dialogueByTask)
        }
    }

    func loadRelatedTaskRows(
        ids: [UUID],
        projectID: UUID?,
        database: Database
    ) throws -> [UUID: Row] {
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
            database,
            sql: taskSQL,
            arguments: StatementArguments(taskArgs)
        )
        return Dictionary(
            uniqueKeysWithValues: taskRows.compactMap { row in
                guard let idString = row["id"] as String?,
                      let id = UUID(uuidString: idString)
                else { return nil }
                return (id, row)
            }
        )
    }

    func loadRelatedDialogue(
        ids: [UUID],
        tasksByID: [UUID: Row],
        database: Database
    ) throws -> [UUID: [RelatedDialogueLine]] {
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
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
            database,
            sql: dialogueSQL,
            arguments: StatementArguments(dialogueArgs)
        )
        var dialogueByTask: [UUID: [RelatedDialogueLine]] = [:]
        dialogueByTask.reserveCapacity(tasksByID.count)
        for row in dialogueRows {
            appendRelatedDialogueRow(row, tasksByID: tasksByID, into: &dialogueByTask)
        }
        return dialogueByTask
    }

    func appendRelatedDialogueRow(
        _ row: Row,
        tasksByID: [UUID: Row],
        into dialogueByTask: inout [UUID: [RelatedDialogueLine]]
    ) {
        guard let taskIDString = row["task_id"] as String?,
              let taskID = UUID(uuidString: taskIDString),
              tasksByID[taskID] != nil,
              let kindRaw = row["kind"] as String?,
              let content = row["content"] as String?
        else { return }
        let kind: RelatedDialogueLine.Kind
        switch kindRaw {
        case AgentEventKind.userInput.rawValue:
            kind = .user

        case AgentEventKind.assistantResponse.rawValue:
            kind = .assistant

        default:
            return
        }
        var lines = dialogueByTask[taskID] ?? []
        if lines.count < Self.relatedDialogueLimit {
            lines.append(RelatedDialogueLine(kind: kind, content: content))
            dialogueByTask[taskID] = lines
        }
    }

    func assembleRelatedSnippets(
        ids: [UUID],
        tasksByID: [UUID: Row],
        dialogueByTask: [UUID: [RelatedDialogueLine]]
    ) -> [RelatedTaskContextSnippet] {
        var snippets: [RelatedTaskContextSnippet] = []
        snippets.reserveCapacity(ids.count)
        for id in ids {
            guard let row = tasksByID[id] else { continue }
            let taskProjectID = (row["project_id"] as String?).flatMap(UUID.init(uuidString:))
            snippets.append(
                RelatedTaskContextSnippet(
                    id: id,
                    projectID: taskProjectID,
                    topic: row["topic"],
                    summary: row["summary"],
                    abstract: row["abstract"],
                    recentDialogue: Array((dialogueByTask[id] ?? []).reversed())
                )
            )
        }
        return snippets
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
        try pool.write { database in
            try database.execute(
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
            try database.execute(
                sql: "UPDATE tasks SET updated_at = ?, status = ? WHERE id = ?",
                arguments: [
                    Date.now.timeIntervalSince1970,
                    TaskStatus.active.rawValue,
                    taskID.uuidString,
                ]
            )
        }
    }
}
