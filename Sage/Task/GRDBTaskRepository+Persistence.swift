//
//  GRDBTaskRepository+Persistence.swift
//  Sage
//
//  Task upsert / relations / plan sync / event insert / legacy JSON import.
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    func upsertTask(_ task: TaskRecord, database: Database) throws {
        let payload = encodedTaskColumns(task)
        try database.execute(
            sql: """
            INSERT INTO tasks (
                id, status, project_id, summary, topic, abstract,
                topic_updated_at, activated_skills, work_plan_json,
                working_memory_json, todo_list_json, pending_prompt_json,
                unlocked_mcp_servers_json,
                skill_persist_considered, origin_schedule_id, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                status = excluded.status,
                project_id = excluded.project_id,
                summary = excluded.summary,
                topic = COALESCE(excluded.topic, tasks.topic),
                abstract = COALESCE(excluded.abstract, tasks.abstract),
                topic_updated_at = COALESCE(excluded.topic_updated_at, tasks.topic_updated_at),
                activated_skills = excluded.activated_skills,
                work_plan_json = excluded.work_plan_json,
                working_memory_json = excluded.working_memory_json,
                todo_list_json = excluded.todo_list_json,
                pending_prompt_json = excluded.pending_prompt_json,
                unlocked_mcp_servers_json = excluded.unlocked_mcp_servers_json,
                skill_persist_considered = excluded.skill_persist_considered,
                origin_schedule_id = COALESCE(excluded.origin_schedule_id, tasks.origin_schedule_id),
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
                payload.activatedSkillsJSON,
                payload.workPlanJSON,
                payload.workingMemoryJSON,
                payload.todoListJSON,
                payload.pendingPromptJSON,
                payload.unlockedMCPServersJSON,
                task.skillPersistConsidered ? 1 : 0,
                task.originScheduleID?.uuidString,
                task.createdAt.timeIntervalSince1970,
                task.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    struct EncodedTaskColumns {
        var activatedSkillsJSON: String?
        var workPlanJSON: String?
        var workingMemoryJSON: String?
        var todoListJSON: String?
        var pendingPromptJSON: String?
        var unlockedMCPServersJSON: String?
    }

    func encodedTaskColumns(_ task: TaskRecord) -> EncodedTaskColumns {
        EncodedTaskColumns(
            activatedSkillsJSON: task.activatedSkillNames.isEmpty
                ? nil : encodeJSON(Array(task.activatedSkillNames)),
            workPlanJSON: encodeJSON(task.workPlan),
            workingMemoryJSON: task.workingMemory?.hasContent == true ? encodeJSON(task.workingMemory) : nil,
            todoListJSON: task.todos.isEmpty ? nil : encodeJSON(task.todos),
            pendingPromptJSON: encodeJSON(task.pendingPrompt),
            unlockedMCPServersJSON: task.unlockedMCPServerNames.isEmpty
                ? nil : encodeJSON(task.unlockedMCPServerNames.sorted())
        )
    }

    func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        return (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Entity extraction is not wired yet — skip the DELETE when the in-memory
    /// list is empty (the common hot path) so every commit doesn't touch the table.
    func replaceEntitiesIfNeeded(
        _ entities: [TaskEntity],
        taskID: UUID,
        database: Database
    ) throws {
        guard !entities.isEmpty else { return }
        try database.execute(
            sql: "DELETE FROM task_entities WHERE task_id = ?",
            arguments: [taskID.uuidString]
        )
        for entity in entities {
            try database.execute(
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

    func replaceRelations(
        _ relatedTaskIDs: [UUID],
        taskID: UUID,
        database: Database
    ) throws {
        // Schema stores UUIDs as TEXT.
        let existingIDs = try String.fetchAll(
            database,
            sql: """
            SELECT target_task_id FROM task_relations
            WHERE source_task_id = ?
            ORDER BY position ASC
            """,
            arguments: [taskID.uuidString]
        )
        .compactMap(UUID.init(uuidString:))
        guard existingIDs != relatedTaskIDs else { return }

        try database.execute(
            sql: "DELETE FROM task_relations WHERE source_task_id = ?",
            arguments: [taskID.uuidString]
        )
        for (position, relatedID) in relatedTaskIDs.enumerated() {
            try database.execute(
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

    /// Sync plan graph: same plan id → upsert steps; otherwise full replace.
    func syncPendingPlan(
        _ plan: AgentPlan?,
        taskID: UUID,
        database: Database
    ) throws {
        guard let plan else {
            try database.execute(
                sql: "DELETE FROM plans WHERE task_id = ?",
                arguments: [taskID.uuidString]
            )
            return
        }

        let existingPlanID = try String.fetchOne(
            database,
            sql: "SELECT id FROM plans WHERE task_id = ?",
            arguments: [taskID.uuidString]
        )

        if existingPlanID == plan.id.uuidString {
            try database.execute(
                sql: "UPDATE plans SET summary = ? WHERE id = ?",
                arguments: [plan.summary, plan.id.uuidString]
            )

            let existingStepIDs = Set(
                try String.fetchAll(
                    database,
                    sql: "SELECT id FROM plan_steps WHERE plan_id = ?",
                    arguments: [plan.id.uuidString]
                )
            )
            var keepStepIDs = Set<String>()
            for (position, step) in plan.steps.enumerated() {
                keepStepIDs.insert(step.id.uuidString)
                try upsertPlanStep(
                    step,
                    planID: plan.id,
                    position: position,
                    existingIDs: existingStepIDs,
                    database: database
                )
            }

            let stale = existingStepIDs.subtracting(keepStepIDs)
            for stepID in stale {
                try database.execute(
                    sql: "DELETE FROM plan_steps WHERE id = ? AND plan_id = ?",
                    arguments: [stepID, plan.id.uuidString]
                )
            }
            return
        }

        try replacePendingPlan(plan, taskID: taskID, database: database)
    }

    func upsertPlanStep(
        _ step: AgentStep,
        planID: UUID,
        position: Int,
        existingIDs: Set<String>,
        database: Database
    ) throws {
        if existingIDs.contains(step.id.uuidString) {
            try database.execute(
                sql: """
                UPDATE plan_steps
                SET position = ?, tool_call_id = ?, tool_name = ?,
                    arguments_json = ?, title = ?, status = ?, result = ?
                WHERE id = ? AND plan_id = ?
                """,
                arguments: [
                    position,
                    step.toolCallID,
                    step.toolName,
                    step.argumentsJSON,
                    step.title,
                    step.status.rawValue,
                    step.result,
                    step.id.uuidString,
                    planID.uuidString,
                ]
            )
            return
        }
        try insertPlanStep(step, planID: planID, position: position, database: database)
    }

    func insertPlanStep(
        _ step: AgentStep,
        planID: UUID,
        position: Int,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO plan_steps (
                id, plan_id, position, tool_call_id, tool_name,
                arguments_json, title, status, result
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                step.id.uuidString,
                planID.uuidString,
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

    func replacePendingPlan(
        _ plan: AgentPlan,
        taskID: UUID,
        database: Database
    ) throws {
        try database.execute(
            sql: "DELETE FROM plans WHERE task_id = ?",
            arguments: [taskID.uuidString]
        )

        try database.execute(
            sql: "INSERT INTO plans (id, task_id, summary) VALUES (?, ?, ?)",
            arguments: [
                plan.id.uuidString,
                taskID.uuidString,
                plan.summary,
            ]
        )
        for (position, step) in plan.steps.enumerated() {
            try insertPlanStep(step, planID: plan.id, position: position, database: database)
        }
    }

    func insertEvent(
        _ event: AgentEvent,
        taskID: UUID,
        sequence: Int,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO events (
                id, task_id, sequence, kind, content, tool_call_id, protected, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                event.id.uuidString,
                taskID.uuidString,
                sequence,
                event.kind.rawValue,
                event.content,
                event.toolCallID,
                event.protected ? 1 : 0,
                event.createdAt.timeIntervalSince1970,
            ]
        )
        try insertEventToolCalls(event, database: database)
        try insertEventContext(event, database: database)
    }

    func insertEventToolCalls(_ event: AgentEvent, database: Database) throws {
        for (position, call) in (event.toolCalls ?? []).enumerated() {
            try database.execute(
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
    }

    func insertEventContext(_ event: AgentEvent, database: Database) throws {
        guard let context = event.context else { return }
        try database.execute(
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
            try database.execute(
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

    /// Imports the short-lived JSON prototype once, then removes it.
}
