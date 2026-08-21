//
//  GRDBTaskSchema+Migrations.swift
//  Sage
//

import Foundation
import GRDB

nonisolated extension GRDBTaskSchema {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        registerCoreMigrations(&migrator)
        registerScheduleAndTaskMigrations(&migrator)
    }

    static func registerCoreMigrations(_ migrator: inout DatabaseMigrator) {
        registerFoundationMigrations(&migrator)
        registerTaskFeatureMigrations(&migrator)
    }

    static func registerFoundationMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("createTaskStore") { database in
            try database.execute(sql: schemaSQL)
        }
        migrator.registerMigration("addTopicFields") { database in
            try database.execute(sql: """
                ALTER TABLE tasks ADD COLUMN topic TEXT;
                ALTER TABLE tasks ADD COLUMN abstract TEXT;
                ALTER TABLE tasks ADD COLUMN topic_updated_at REAL;
            """)
        }
        migrator.registerMigration("addProjects") { database in
            try database.execute(sql: """
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
        migrator.registerMigration("addLastGeneralTask") { database in
            try database.execute(sql: """
                ALTER TABLE app_state ADD COLUMN last_general_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL;
            """)
        }
    }

    static func registerTaskFeatureMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addActivatedSkills") { database in
            try database.execute(sql: """
                ALTER TABLE tasks ADD COLUMN activated_skills TEXT;
            """)
        }
        migrator.registerMigration("addWorkPlan") { database in
            try addColumnIfMissing(
                database,
                table: "tasks",
                column: "work_plan_json",
                sql: "ALTER TABLE tasks ADD COLUMN work_plan_json TEXT;"
            )
        }
        migrator.registerMigration("addSkillPersistConsidered") { database in
            try addColumnIfMissing(
                database,
                table: "tasks",
                column: "skill_persist_considered",
                sql: """
                    ALTER TABLE tasks ADD COLUMN skill_persist_considered INTEGER NOT NULL DEFAULT 0;
                """
            )
        }
        migrator.registerMigration("addEventProtected") { database in
            try addColumnIfMissing(
                database,
                table: "events",
                column: "protected",
                sql: """
                    ALTER TABLE events ADD COLUMN protected INTEGER NOT NULL DEFAULT 0;
                """
            )
        }
    }
}
