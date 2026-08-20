//
//  GRDBTaskRepository+Persistence.swift
//  Sage
//
//  Task upsert / relations / plan sync / event insert / legacy JSON import.
//

import Foundation
import GRDB

extension GRDBTaskRepository {
    func upsertTask(_ task: TaskRecord, database db: Database) throws {
        // COALESCE keeps an existing topic when a concurrent in-memory snapshot
        // still has nil (topic generation racing with commit/mutate).
        let activatedSkillsJSON: String? = task.activatedSkillNames.isEmpty
            ? nil
            : (try? JSONEncoder().encode(Array(task.activatedSkillNames)))
                .flatMap { String(data: $0, encoding: .utf8) }
        let workPlanJSON: String? = task.workPlan.flatMap { plan in
            (try? JSONEncoder().encode(plan))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        let workingMemoryJSON: String? = task.workingMemory.flatMap { memory in
            guard memory.hasContent else { return nil }
            return (try? JSONEncoder().encode(memory))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        let todoListJSON: String? = task.todos.isEmpty
            ? nil
            : (try? JSONEncoder().encode(task.todos))
                .flatMap { String(data: $0, encoding: .utf8) }
        let pendingPromptJSON: String? = task.pendingPrompt.flatMap { prompt in
            (try? JSONEncoder().encode(prompt))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        let unlockedMCPServersJSON: String? = task.unlockedMCPServerNames.isEmpty
            ? nil
            : (try? JSONEncoder().encode(task.unlockedMCPServerNames.sorted()))
                .flatMap { String(data: $0, encoding: .utf8) }

        try db.execute(
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
                activatedSkillsJSON,
                workPlanJSON,
                workingMemoryJSON,
                todoListJSON,
                pendingPromptJSON,
                unlockedMCPServersJSON,
                task.skillPersistConsidered ? 1 : 0,
                task.originScheduleID?.uuidString,
                task.createdAt.timeIntervalSince1970,
                task.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    /// Entity extraction is not wired yet — skip the DELETE when the in-memory
    /// list is empty (the common hot path) so every commit doesn't touch the table.
    func replaceEntitiesIfNeeded(
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

    func replaceRelations(
        _ relatedTaskIDs: [UUID],
        taskID: UUID,
        database db: Database
    ) throws {
        // Schema stores UUIDs as TEXT.
        let existingIDs = try String.fetchAll(
            db,
            sql: """
            SELECT target_task_id FROM task_relations
            WHERE source_task_id = ?
            ORDER BY position ASC
            """,
            arguments: [taskID.uuidString]
        ).compactMap(UUID.init(uuidString:))
        guard existingIDs != relatedTaskIDs else { return }

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

    /// Sync plan graph: same plan id → upsert steps; otherwise full replace.
    func syncPendingPlan(
        _ plan: AgentPlan?,
        taskID: UUID,
        database db: Database
    ) throws {
        guard let plan else {
            try db.execute(
                sql: "DELETE FROM plans WHERE task_id = ?",
                arguments: [taskID.uuidString]
            )
            return
        }

        let existingPlanID = try String.fetchOne(
            db,
            sql: "SELECT id FROM plans WHERE task_id = ?",
            arguments: [taskID.uuidString]
        )

        if existingPlanID == plan.id.uuidString {
            try db.execute(
                sql: "UPDATE plans SET summary = ? WHERE id = ?",
                arguments: [plan.summary, plan.id.uuidString]
            )

            let existingStepIDs = Set(
                try String.fetchAll(
                    db,
                    sql: "SELECT id FROM plan_steps WHERE plan_id = ?",
                    arguments: [plan.id.uuidString]
                )
            )
            var keepStepIDs = Set<String>()
            for (position, step) in plan.steps.enumerated() {
                keepStepIDs.insert(step.id.uuidString)
                if existingStepIDs.contains(step.id.uuidString) {
                    try db.execute(
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
                            plan.id.uuidString,
                        ]
                    )
                } else {
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

            let stale = existingStepIDs.subtracting(keepStepIDs)
            for stepID in stale {
                try db.execute(
                    sql: "DELETE FROM plan_steps WHERE id = ? AND plan_id = ?",
                    arguments: [stepID, plan.id.uuidString]
                )
            }
            return
        }

        try replacePendingPlan(plan, taskID: taskID, database: db)
    }

    func replacePendingPlan(
        _ plan: AgentPlan,
        taskID: UUID,
        database db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM plans WHERE task_id = ?",
            arguments: [taskID.uuidString]
        )

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

    func insertEvent(
        _ event: AgentEvent,
        taskID: UUID,
        sequence: Int,
        database db: Database
    ) throws {
        try db.execute(
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
    func importLegacyJSONIfNeeded(into pool: DatabasePool) throws {
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
                try syncPendingPlan(task.pendingPlan, taskID: task.id, database: db)
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

}
