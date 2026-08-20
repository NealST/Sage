//
//  GRDBTaskSchema.swift
//  Sage
//
//  Schema SQL + migrations for GRDBTaskRepository.
//

import Foundation
import GRDB

nonisolated enum GRDBTaskSchema {
    static let schemaSQL = """
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
        protected INTEGER NOT NULL DEFAULT 0,
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

    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("createTaskStore") { db in
            try db.execute(sql: schemaSQL)
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
        migrator.registerMigration("addActivatedSkills") { db in
            try db.execute(sql: """
                ALTER TABLE tasks ADD COLUMN activated_skills TEXT;
            """)
        }
        migrator.registerMigration("addWorkPlan") { db in
            let hasWorkPlan = try db.columns(in: "tasks").contains { $0.name == "work_plan_json" }
            if !hasWorkPlan {
                try db.execute(sql: """
                    ALTER TABLE tasks ADD COLUMN work_plan_json TEXT;
                """)
            }
        }
        migrator.registerMigration("addSkillPersistConsidered") { db in
            let hasColumn = try db.columns(in: "tasks").contains { $0.name == "skill_persist_considered" }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE tasks ADD COLUMN skill_persist_considered INTEGER NOT NULL DEFAULT 0;
                """)
            }
        }
        migrator.registerMigration("addEventProtected") { db in
            // Idempotent: base `schemaSQL` may already include the column on fresh installs.
            let hasProtected = try db.columns(in: "events").contains { $0.name == "protected" }
            if !hasProtected {
                try db.execute(sql: """
                    ALTER TABLE events ADD COLUMN protected INTEGER NOT NULL DEFAULT 0;
                """)
            }
        }
        migrator.registerMigration("addSchedules") { db in
            try db.execute(sql: """
                CREATE TABLE schedules (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
                    prompt TEXT,
                    command TEXT,
                    cadence_kind TEXT NOT NULL,
                    cadence_json TEXT NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    status TEXT NOT NULL,
                    next_fire_at REAL,
                    last_fire_at REAL,
                    last_status TEXT,
                    frozen_work_plan_json TEXT,
                    frozen_skill_names TEXT,
                    origin_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE INDEX schedules_due
                ON schedules(enabled, next_fire_at);

                CREATE INDEX schedules_project
                ON schedules(project_id);

                CREATE TABLE schedule_runs (
                    id TEXT PRIMARY KEY NOT NULL,
                    schedule_id TEXT NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
                    started_at REAL NOT NULL,
                    ended_at REAL,
                    exit_code INTEGER,
                    output_excerpt TEXT
                );
            """)
        }
        migrator.registerMigration("addScheduleLastRunTask") { db in
            let hasColumn = try db.columns(in: "schedules").contains { $0.name == "last_run_task_id" }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE schedules
                    ADD COLUMN last_run_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL;
                """)
            }
        }
        migrator.registerMigration("addScheduleWorkingDirectory") { db in
            let hasColumn = try db.columns(in: "schedules").contains { $0.name == "working_directory" }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE schedules
                    ADD COLUMN working_directory TEXT;
                """)
            }
        }
        migrator.registerMigration("addTaskScheduleOrigin") { db in
            let hasColumn = try db.columns(in: "tasks").contains { $0.name == "origin_schedule_id" }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE tasks
                    ADD COLUMN origin_schedule_id TEXT REFERENCES schedules(id) ON DELETE SET NULL;
                """)
            }
        }
        migrator.registerMigration("indexScheduleRunsByScheduleStarted") { db in
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS schedule_runs_schedule_started
                ON schedule_runs(schedule_id, started_at);
            """)
        }
        migrator.registerMigration("addTaskWorkingMemory") { db in
            let hasColumn = try db.columns(in: "tasks").contains { $0.name == "working_memory_json" }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE tasks
                    ADD COLUMN working_memory_json TEXT;
                """)
            }
        }
        migrator.registerMigration("addTaskTodoList") { db in
            let hasColumn = try db.columns(in: "tasks").contains { $0.name == "todo_list_json" }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE tasks
                    ADD COLUMN todo_list_json TEXT;
                """)
            }
        }
        migrator.registerMigration("addTaskPendingPrompt") { db in
            let hasColumn = try db.columns(in: "tasks").contains { $0.name == "pending_prompt_json" }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE tasks
                    ADD COLUMN pending_prompt_json TEXT;
                """)
            }
        }
        migrator.registerMigration("addTaskUnlockedMCPServers") { db in
            let hasColumn = try db.columns(in: "tasks").contains {
                $0.name == "unlocked_mcp_servers_json"
            }
            if !hasColumn {
                try db.execute(sql: """
                    ALTER TABLE tasks
                    ADD COLUMN unlocked_mcp_servers_json TEXT;
                """)
            }
        }
    }
}
