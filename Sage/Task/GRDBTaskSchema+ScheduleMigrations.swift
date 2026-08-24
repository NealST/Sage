//
//  GRDBTaskSchema+ScheduleMigrations.swift
//  Sage
//

import Foundation
import GRDB

nonisolated extension GRDBTaskSchema {
    static func registerScheduleAndTaskMigrations(_ migrator: inout DatabaseMigrator) {
        registerScheduleTableMigrations(&migrator)
        registerTaskColumnMigrations(&migrator)
    }

    static func registerScheduleTableMigrations(_ migrator: inout DatabaseMigrator) {
        registerScheduleCreateMigrations(&migrator)
        registerScheduleColumnMigrations(&migrator)
    }

    static func registerScheduleCreateMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addSchedules") { database in
            try database.execute(sql: """
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
    }

    static func registerScheduleColumnMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addScheduleLastRunTask") { database in
            try addColumnIfMissing(
                database,
                table: "schedules",
                column: "last_run_task_id",
                sql: """
                    ALTER TABLE schedules
                    ADD COLUMN last_run_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL;
                """
            )
        }
        migrator.registerMigration("addScheduleWorkingDirectory") { database in
            try addColumnIfMissing(
                database,
                table: "schedules",
                column: "working_directory",
                sql: "ALTER TABLE schedules ADD COLUMN working_directory TEXT;"
            )
        }
        migrator.registerMigration("indexScheduleRunsByScheduleStarted") { database in
            try database.execute(sql: """
                CREATE INDEX IF NOT EXISTS schedule_runs_schedule_started
                ON schedule_runs(schedule_id, started_at);
            """)
        }
    }

    static func registerTaskColumnMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addTaskScheduleOrigin") { database in
            try addColumnIfMissing(
                database,
                table: "tasks",
                column: "origin_schedule_id",
                sql: """
                    ALTER TABLE tasks
                    ADD COLUMN origin_schedule_id TEXT REFERENCES schedules(id) ON DELETE SET NULL;
                """
            )
        }
        migrator.registerMigration("addTaskWorkingMemory") { database in
            try addColumnIfMissing(
                database,
                table: "tasks",
                column: "working_memory_json",
                sql: "ALTER TABLE tasks ADD COLUMN working_memory_json TEXT;"
            )
        }
        migrator.registerMigration("addTaskTodoList") { database in
            try addColumnIfMissing(
                database,
                table: "tasks",
                column: "todo_list_json",
                sql: "ALTER TABLE tasks ADD COLUMN todo_list_json TEXT;"
            )
        }
        migrator.registerMigration("addTaskPendingPrompt") { database in
            try addColumnIfMissing(
                database,
                table: "tasks",
                column: "pending_prompt_json",
                sql: "ALTER TABLE tasks ADD COLUMN pending_prompt_json TEXT;"
            )
        }
        migrator.registerMigration("addTaskUnlockedMCPServers") { database in
            try addColumnIfMissing(
                database,
                table: "tasks",
                column: "unlocked_mcp_servers_json",
                sql: "ALTER TABLE tasks ADD COLUMN unlocked_mcp_servers_json TEXT;"
            )
        }
        migrator.registerMigration("addEventAttachments") { database in
            try database.execute(sql: """
                CREATE TABLE IF NOT EXISTS event_attachments (
                    event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    path TEXT NOT NULL,
                    is_ephemeral INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(event_id, position)
                );

                CREATE INDEX IF NOT EXISTS event_attachments_event
                ON event_attachments(event_id, position);
            """)
        }
    }

    static func addColumnIfMissing(
        _ database: Database,
        table: String,
        column: String,
        sql: String
    ) throws {
        let hasColumn = try database.columns(in: table).contains { $0.name == column }
        if !hasColumn {
            try database.execute(sql: sql)
        }
    }
}
