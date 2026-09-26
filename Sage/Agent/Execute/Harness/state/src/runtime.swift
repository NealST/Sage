//
//  runtime.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Facade that compiles without sqlx/GRDB pools. Methods that need SQLite
//  throw `StateRuntimeError.sqliteUnavailable`. Large runtimes (memories,
//  threads, goals, logs) are deferred; `MemoryStore` and `GoalStore` are
//  thin holders so smaller extension files can attach.
//

import CodexProtocol
import Foundation

let MEMORIES_V2_DB_FILENAME = "memories_v2_1.sqlite"

/// Partition is the retained-log-content bucket we cap at 10 MiB.
let LOG_PARTITION_SIZE_LIMIT_BYTES: Int64 = 10 * 1024 * 1024
let LOG_PARTITION_ROW_LIMIT: Int64 = 1_000

public enum StateRuntimeError: Error, Equatable, Sendable {
    case sqliteUnavailable(String)
    case invalidInput(String)
}

/// Thin stand-in for `runtime/goals.rs` `GoalStore`.
public final class GoalStore: @unchecked Sendable {
    public init() {}

    public func close() async {}
}

/// Thin stand-in for `runtime/memories.rs` `MemoryStore`.
public final class MemoryStore: @unchecked Sendable {
    public init() {}

    public func close() async {}

    public func clearMemoryData() async throws {
        throw StateRuntimeError.sqliteUnavailable("memories")
    }

    public func deleteThreadMemory(_ threadId: ThreadId) async throws {
        throw StateRuntimeError.sqliteUnavailable("memories")
    }
}

/// Preferred entrypoint: owns configuration. SQLite pools land with GRDB.
public final class StateRuntime: @unchecked Sendable {
    public let sqlite: SqliteConfig
    public let defaultProvider: String
    public let threadGoals: GoalStore
    public let memories: MemoryStore
    public let threadQueue: SqliteQueueStore
    var threadUpdatedAtMillis: Int64
    var threadRecencyAtMillis: Int64

    public init(sqlite: SqliteConfig, defaultProvider: String) {
        self.sqlite = sqlite
        self.defaultProvider = defaultProvider
        self.threadGoals = GoalStore()
        self.memories = MemoryStore()
        self.threadQueue = SqliteQueueStore()
        self.threadUpdatedAtMillis = 0
        self.threadRecencyAtMillis = 0
    }

    /// Initialize the state runtime using the provided SQLite configuration.
    ///
    /// Opens (and migrates) the SQLite databases under `sqlite_home` once GRDB
    /// is wired. Today this only ensures the home directory exists.
    public static func initialize(
        sqlite: SqliteConfig,
        defaultProvider: String,
        telemetryOverride: (any DbTelemetry)? = nil
    ) throws -> StateRuntime {
        try FileManager.default.createDirectory(
            atPath: sqlite.home,
            withIntermediateDirectories: true
        )
        _ = telemetryOverride
        _ = runtimeStateMigrator()
        _ = runtimeLogsMigrator()
        _ = runtimeGoalsMigrator()
        _ = runtimeMemoriesMigrator()
        _ = runtimeQueueMigrator()
        return StateRuntime(sqlite: sqlite, defaultProvider: defaultProvider)
    }

    public func close() async {
        await threadQueue.close()
        await memories.close()
        await threadGoals.close()
    }

    public static func clearMemoryDataInSqliteHome(_ sqlite: SqliteConfig) async throws -> Bool {
        let cleared = false
        for version in [MemoryVersion.v1, MemoryVersion.v2] {
            let path = memoriesDbPath(sqlite, version: version)
            if !FileManager.default.fileExists(atPath: path) {
                continue
            }
            throw StateRuntimeError.sqliteUnavailable(
                version == .v1 ? "memories" : "memories_v2"
            )
        }
        return cleared
    }
}

func memoriesDbPath(_ sqlite: SqliteConfig, version: MemoryVersion) -> String {
    switch version {
    case .v1:
        return sqlite.memoriesDbPath()
    case .v2:
        return memoriesV2DbPath(sqlite)
    }
}

func memoriesV2DbPath(_ sqlite: SqliteConfig) -> String {
    (sqlite.home as NSString).appendingPathComponent(MEMORIES_V2_DB_FILENAME)
}

/// Open and migrate the rebuildable paginated thread-history database.
public func openThreadHistoryDb(_ sqlite: SqliteConfig) async throws {
    _ = runtimeThreadHistoryMigrator()
    throw StateRuntimeError.sqliteUnavailable("thread_history")
}

func ensureBackfillStateRow() async throws {
    throw StateRuntimeError.sqliteUnavailable("state")
}

/// Integrity-check rows, including those emitted before interruption.
public enum SqliteIntegrityCheck: Equatable, Sendable {
    case complete([String])
    case timedOut([String])
}

/// Run SQLite's built-in integrity check against an existing database file.
public func sqliteIntegrityCheck(
    sqlite: SqliteConfig,
    path: String,
    deadline: Date? = nil
) async throws -> SqliteIntegrityCheck {
    _ = sqlite
    _ = path
    _ = deadline
    throw StateRuntimeError.sqliteUnavailable("integrity_check")
}
