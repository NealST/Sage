//
//  sqlite.swift
//  CodexState
//
//  Port of codex-rs/state/src/sqlite.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Connection pooling / sqlx maps to GRDB in later files. This file keeps
//  the database filenames and `SqliteConfig` path helpers.
//

import Foundation

public let LOGS_DB_FILENAME = "logs_2.sqlite"
public let GOALS_DB_FILENAME = "goals_1.sqlite"
public let MEMORIES_DB_FILENAME = "memories_1.sqlite"
public let QUEUE_DB_FILENAME = "queue_1.sqlite"
public let STATE_DB_FILENAME = "state_5.sqlite"
public let THREAD_HISTORY_DB_FILENAME = "thread_history_1.sqlite"

public struct SqliteConfig: Equatable, Sendable {
    public var sqliteHome: String

    public init(sqliteHome: String = "") {
        self.sqliteHome = sqliteHome
    }

    public static func fromSqliteHome(_ sqliteHome: String) -> SqliteConfig {
        SqliteConfig(sqliteHome: sqliteHome)
    }

    public static func newForTesting(_ sqliteHome: String) -> SqliteConfig {
        fromSqliteHome(sqliteHome)
    }

    public var home: String { sqliteHome }

    public func stateDbPath() -> String {
        (home as NSString).appendingPathComponent(STATE_DB_FILENAME)
    }

    public func logsDbPath() -> String {
        (home as NSString).appendingPathComponent(LOGS_DB_FILENAME)
    }

    public func goalsDbPath() -> String {
        (home as NSString).appendingPathComponent(GOALS_DB_FILENAME)
    }

    public func memoriesDbPath() -> String {
        (home as NSString).appendingPathComponent(MEMORIES_DB_FILENAME)
    }

    public func queueDbPath() -> String {
        (home as NSString).appendingPathComponent(QUEUE_DB_FILENAME)
    }

    public func threadHistoryDbPath() -> String {
        (home as NSString).appendingPathComponent(THREAD_HISTORY_DB_FILENAME)
    }
}
