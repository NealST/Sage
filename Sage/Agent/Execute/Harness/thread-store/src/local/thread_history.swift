//
//  thread_history.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_history.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SQLite projection (sqlx) throws until GRDB is wired. No schema is invented.
//  `projectionState` returns nil when `stateDb()` is nil or the history DB
//  file is absent (matches Rust `state_db.is_none()` / `try_exists`).
//  `ThreadHistoryChangeSet` is unported; `ProjectedRolloutLine.changes` is
//  `JSONValue` (empty object stands in for the default change set).
//

import CodexProtocol
import CodexState
import Foundation

/// A valid complete rollout line with its absolute byte span in durable JSONL.
///
/// `startByteOffset..<endByteOffset` includes the terminating newline.
struct ProjectedRolloutLine {
    var ordinal: UInt64
    var startByteOffset: UInt64
    var endByteOffset: UInt64
    var fallbackCreatedAtMs: Int64?
    /// App-server `ThreadHistoryChangeSet` is not ported; empty object is default.
    var changes: JSONValue
    var realtimeItem: RealtimeItem?
}

/// One ordered update to apply while advancing a rollout projection checkpoint.
///
/// Skipped ordinal ranges keep the byte and ordinal checkpoints describing the same durable
/// prefix even when a complete rollout line cannot be projected.
enum RolloutProjectionStep {
    case line(ProjectedRolloutLine)
    case skippedOrdinalRange(startOrdinal: UInt64, endOrdinalExclusive: UInt64)
}

struct RolloutProjectionState {
    var nextByteOffset: UInt64
    var nextOrdinal: UInt64
}

func projectionState(
    store: LocalThreadStore,
    threadId: ThreadId
) throws -> RolloutProjectionState? {
    if store.stateDb() == nil {
        return nil
    }
    let dbPath = store.config.sqlite.threadHistoryDbPath()
    if !FileManager.default.fileExists(atPath: dbPath) {
        return nil
    }
    _ = threadId
    throw threadHistoryError("SQLite projection requires GRDB")
}

func applyProjection(
    store: LocalThreadStore,
    threadId: ThreadId,
    startOffset: UInt64,
    nextOffset: UInt64,
    initialOrdinal: UInt64,
    projections: [RolloutProjectionStep]
) throws {
    _ = (store, threadId, startOffset, nextOffset, initialOrdinal, projections)
    throw threadHistoryError("SQLite projection requires GRDB")
}

func deleteThread(
    store: LocalThreadStore,
    threadId: ThreadId
) throws {
    _ = threadId
    let dbPath = store.config.sqlite.threadHistoryDbPath()
    if !FileManager.default.fileExists(atPath: dbPath) {
        return
    }
    throw threadHistoryDeleteError("SQLite projection requires GRDB")
}

func sqliteInteger(_ value: UInt64, field: String) throws -> Int64 {
    guard let converted = Int64(exactly: value) else {
        throw ThreadStoreError.internal("\(field) exceeds SQLite integer range")
    }
    return converted
}

func threadHistoryError(_ err: Any) -> ThreadStoreError {
    .internal("failed to access thread history: \(err)")
}

func threadHistoryDeleteError(_ err: Any) -> ThreadStoreError {
    .internal("failed to delete thread history: \(err)")
}

func paginatedThreadsUnsupported() -> ThreadStoreError {
    .unsupported(operation: "paginated_threads")
}
