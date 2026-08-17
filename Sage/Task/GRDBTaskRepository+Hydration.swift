//
//  GRDBTaskRepository+Hydration.swift
//  Sage
//
//  Row → TaskRecord / ProjectRecord / events / plans.
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    // MARK: - Hydration

    func loadTask(
        from row: Row,
        database db: Database,
        includeHistory: Bool = true
    ) throws -> TaskRecord? {
        guard
            let id = UUID(uuidString: row["id"]),
            let status = TaskStatus(rawValue: row["status"])
        else {
            return nil
        }

        let topicUpdatedAt: Date? = (row["topic_updated_at"] as Double?)
            .map { Date(timeIntervalSince1970: $0) }

        let projectID = (row["project_id"] as String?).flatMap(UUID.init(uuidString:))

        let activatedSkills: Set<String>
        if let json: String = row["activated_skills"],
           let data = json.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            activatedSkills = Set(names)
        } else {
            activatedSkills = []
        }

        let workPlan: WorkPlan?
        if let json: String = row["work_plan_json"],
           let data = json.data(using: .utf8) {
            workPlan = try? JSONDecoder().decode(WorkPlan.self, from: data)
        } else {
            workPlan = nil
        }

        return TaskRecord(
            id: id,
            status: status,
            projectID: projectID,
            summary: row["summary"],
            topic: row["topic"],
            abstract: row["abstract"],
            topicUpdatedAt: topicUpdatedAt,
            events: includeHistory ? try loadEvents(taskID: id, database: db) : [],
            workPlan: workPlan,
            pendingPlan: includeHistory ? try loadPlan(taskID: id, database: db) : nil,
            // Entity extraction is not wired; skip the table read on the hot path.
            entities: [],
            relatedTaskIDs: try loadRelations(taskID: id, database: db),
            activatedSkillNames: activatedSkills,
            skillPersistConsidered: {
                if let flag = row["skill_persist_considered"] as Int? { return flag != 0 }
                if let flag = row["skill_persist_considered"] as Bool? { return flag }
                return false
            }(),
            originScheduleID: (row["origin_schedule_id"] as String?)
                .flatMap(UUID.init(uuidString:)),
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }

    func loadProject(id: UUID, database db: Database) throws -> ProjectRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM projects WHERE id = ?",
            arguments: [id.uuidString]
        ) else { return nil }
        return Self.projectRecord(from: row)
    }

    func loadProject(rootPath: String, database db: Database) throws -> ProjectRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM projects WHERE root_path = ?",
            arguments: [rootPath]
        ) else { return nil }
        return Self.projectRecord(from: row)
    }

    func loadRecentProjects(limit: Int, database db: Database) throws -> [ProjectRecord] {
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

    func upsertProject(_ project: ProjectRecord, database db: Database) throws {
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

    static func projectRecord(from row: Row) -> ProjectRecord? {
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

    static func taskSummary(from row: Row) -> TaskSummary? {
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
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
            originScheduleID: (row["origin_schedule_id"] as String?)
                .flatMap(UUID.init(uuidString:))
        )
    }

    func loadEvents(taskID: UUID, database db: Database) throws -> [AgentEvent] {
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
            let protectedValue: Bool
            if let intFlag = row["protected"] as Int? {
                protectedValue = intFlag != 0
            } else if let boolFlag = row["protected"] as Bool? {
                protectedValue = boolFlag
            } else {
                protectedValue = false
            }
            return AgentEvent(
                id: id,
                kind: kind,
                content: row["content"],
                toolCallID: row["tool_call_id"],
                toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                context: contextsByEvent[idString],
                protected: protectedValue,
                createdAt: Date(timeIntervalSince1970: row["created_at"])
            )
        }
    }

    func loadToolCalls(
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

    func loadContexts(
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

    func loadRelations(taskID: UUID, database db: Database) throws -> [UUID] {
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

    func loadPlan(taskID: UUID, database db: Database) throws -> AgentPlan? {
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
