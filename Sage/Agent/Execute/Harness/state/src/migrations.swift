//
//  migrations.swift
//  CodexState
//
//  Port of codex-rs/state/src/migrations.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx `Migrator` / embedded SQL is stubbed as named descriptors. GRDB
//  migrators will attach to these names. Legacy recency repair is a no-op.
//

import Foundation

/// Named sqlx migrator set embedded from `./migrations`.
public let STATE_MIGRATOR = StateMigrator(name: "state", ignoreMissing: false)
/// Named sqlx migrator set embedded from `./logs_migrations`.
public let LOGS_MIGRATOR = StateMigrator(name: "logs", ignoreMissing: false)
/// Named sqlx migrator set embedded from `./goals_migrations`.
public let GOALS_MIGRATOR = StateMigrator(name: "goals", ignoreMissing: false)
/// Named sqlx migrator set embedded from `./memory_migrations`.
public let MEMORIES_MIGRATOR = StateMigrator(name: "memories", ignoreMissing: false)
/// Named sqlx migrator set embedded from `./queue_migrations`.
public let QUEUE_MIGRATOR = StateMigrator(name: "queue", ignoreMissing: false)
/// Named sqlx migrator set embedded from `./thread_history_migrations`.
public let THREAD_HISTORY_MIGRATOR = StateMigrator(name: "thread_history", ignoreMissing: false)

/// Descriptor standing in for `sqlx::migrate::Migrator`.
public struct StateMigrator: Equatable, Sendable {
    public var name: String
    public var ignoreMissing: Bool

    public init(name: String, ignoreMissing: Bool) {
        self.name = name
        self.ignoreMissing = ignoreMissing
    }
}

/// Allow an older Codex binary to open a database that has already been
/// migrated by a newer binary running in parallel.
private func runtimeMigrator(_ base: StateMigrator) -> StateMigrator {
    StateMigrator(name: base.name, ignoreMissing: true)
}

func runtimeStateMigrator() -> StateMigrator {
    runtimeMigrator(STATE_MIGRATOR)
}

func runtimeLogsMigrator() -> StateMigrator {
    runtimeMigrator(LOGS_MIGRATOR)
}

func runtimeGoalsMigrator() -> StateMigrator {
    runtimeMigrator(GOALS_MIGRATOR)
}

func runtimeMemoriesMigrator() -> StateMigrator {
    runtimeMigrator(MEMORIES_MIGRATOR)
}

func runtimeQueueMigrator() -> StateMigrator {
    runtimeMigrator(QUEUE_MIGRATOR)
}

func runtimeThreadHistoryMigrator() -> StateMigrator {
    runtimeMigrator(THREAD_HISTORY_MIGRATOR)
}

/// Repair for a legacy recency migration version (sqlx `_sqlx_migrations`).
func repairLegacyRecencyMigrationVersion() throws {
    // No-op until a SQLite connection owns `_sqlx_migrations`.
}
