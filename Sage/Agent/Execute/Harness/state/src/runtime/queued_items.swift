//
//  queued_items.swift
//  CodexState
//
//  Port of codex-rs/state/src/runtime/queued_items.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SQLite-backed queue methods throw until a GRDB pool is attached.
//  `changesSince` with an empty thread list matches upstream (empty result).
//

import CodexProtocol
import Foundation

/// SQLite-backed persistence for durable, thread-scoped user messages.
public final class SqliteQueueStore: @unchecked Sendable {
    public init() {}

    func close() async {}

    /// Observe queue-database commits through one stable SQLite connection.
    public func changeVersion() async throws -> Int64 {
        throw StateRuntimeError.sqliteUnavailable("queue")
    }

    /// Return changed revisions only for the supplied loaded thread IDs.
    public func changesSince(revision: Int64, threadIds: [ThreadId]) async throws -> [(ThreadId, Int64)] {
        if threadIds.isEmpty {
            return []
        }
        _ = revision
        throw StateRuntimeError.sqliteUnavailable("queue")
    }

    public func enqueue(
        threadId: ThreadId,
        payloadJson: String
    ) async throws -> QueuedUserSubmissionRecord {
        _ = threadId
        _ = payloadJson
        _ = MAX_QUEUE_ITEMS
        throw StateRuntimeError.sqliteUnavailable("queue")
    }

    public func listPage(
        threadId: ThreadId,
        offset: Int,
        limit: Int
    ) async throws -> [QueuedUserSubmissionRecord] {
        _ = threadId
        _ = offset
        _ = limit
        throw StateRuntimeError.sqliteUnavailable("queue")
    }

    public func update(
        threadId: ThreadId,
        itemId: String,
        payloadJson: String
    ) async throws -> QueuedUserSubmissionRecord? {
        _ = threadId
        _ = itemId
        _ = payloadJson
        throw StateRuntimeError.sqliteUnavailable("queue")
    }

    public func delete(threadId: ThreadId, itemId: String) async throws -> Bool {
        _ = threadId
        _ = itemId
        throw StateRuntimeError.sqliteUnavailable("queue")
    }

    public func reorder(threadId: ThreadId, orderedIds: [String]) async throws {
        _ = threadId
        _ = orderedIds
        throw StateRuntimeError.sqliteUnavailable("queue")
    }

    func deleteThreadQueue(_ threadId: ThreadId) async throws -> Bool {
        _ = threadId
        throw StateRuntimeError.sqliteUnavailable("queue")
    }
}
