//
//  queue_store.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/queue_store.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `QueuedUserSubmissionRecord` stands in for the unported CodexState model.
//  `LocalQueueStore` is a GRDB stub; `InMemoryQueueStore` owns the behavior.
//

import CodexProtocol
import CodexRollout
import Foundation
import os

/// Maximum number of pending user submissions permitted for one thread.
public let MAX_QUEUE_ITEMS = 100

/// One durable, ordered user submission for a thread.
public struct QueuedUserSubmissionRecord: Codable, Equatable, Sendable {
    public var id: String
    public var threadId: ThreadId
    public var payload: String

    enum CodingKeys: String, CodingKey {
        case id, payload
        case threadId = "thread_id"
    }

    public init(id: String, threadId: ThreadId, payload: String) {
        self.id = id
        self.threadId = threadId
        self.payload = payload
    }
}

/// Storage-neutral persistence for ordered, thread-scoped user messages.
public protocol QueueStore: Sendable {
    func changeVersion() async throws -> Int64
    func changesSince(revision: Int64, threadIds: [ThreadId]) async throws -> [(ThreadId, Int64)]
    func enqueue(threadId: ThreadId, payload: String) async throws -> QueuedUserSubmissionRecord
    func listPage(threadId: ThreadId, offset: Int, limit: Int) async throws -> [QueuedUserSubmissionRecord]
    func update(threadId: ThreadId, itemId: String, payload: String) async throws -> QueuedUserSubmissionRecord?
    func delete(threadId: ThreadId, itemId: String) async throws -> Bool
    func reorder(threadId: ThreadId, itemIds: [String]) async throws
}

/// In-memory `QueueStore` for tests and the pre-GRDB local stub.
public final class InMemoryQueueStore: QueueStore, @unchecked Sendable {
    private struct State {
        var revision: Int64 = 0
        var items: [ThreadId: [QueuedUserSubmissionRecord]] = [:]
        var threadRevisions: [ThreadId: Int64] = [:]
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func changeVersion() async throws -> Int64 {
        lock.withLock { $0.revision }
    }

    public func changesSince(revision: Int64, threadIds: [ThreadId]) async throws -> [(ThreadId, Int64)] {
        lock.withLock { state in
            threadIds.compactMap { threadId in
                guard let threadRevision = state.threadRevisions[threadId],
                      threadRevision > revision else { return nil }
                return (threadId, threadRevision)
            }
        }
    }

    public func enqueue(threadId: ThreadId, payload: String) async throws -> QueuedUserSubmissionRecord {
        try lock.withLock { state in
            var queue = state.items[threadId] ?? []
            if queue.count >= MAX_QUEUE_ITEMS {
                throw ThreadStoreError.invalidRequest(
                    "queue cannot contain more than \(MAX_QUEUE_ITEMS) submissions")
            }
            let record = QueuedUserSubmissionRecord(
                id: ThreadId().description,
                threadId: threadId,
                payload: payload)
            queue.append(record)
            state.items[threadId] = queue
            bump(&state, threadId: threadId)
            return record
        }
    }

    public func listPage(
        threadId: ThreadId,
        offset: Int,
        limit: Int
    ) async throws -> [QueuedUserSubmissionRecord] {
        lock.withLock { state in
            let queue = state.items[threadId] ?? []
            guard offset < queue.count else { return [] }
            let end = min(queue.count, offset + max(limit, 0))
            return Array(queue[offset..<end])
        }
    }

    public func update(
        threadId: ThreadId,
        itemId: String,
        payload: String
    ) async throws -> QueuedUserSubmissionRecord? {
        lock.withLock { state in
            guard var queue = state.items[threadId],
                  let index = queue.firstIndex(where: { $0.id == itemId }) else {
                return nil
            }
            queue[index].payload = payload
            state.items[threadId] = queue
            bump(&state, threadId: threadId)
            return queue[index]
        }
    }

    public func delete(threadId: ThreadId, itemId: String) async throws -> Bool {
        lock.withLock { state in
            guard var queue = state.items[threadId],
                  let index = queue.firstIndex(where: { $0.id == itemId }) else {
                return false
            }
            queue.remove(at: index)
            state.items[threadId] = queue
            bump(&state, threadId: threadId)
            return true
        }
    }

    public func reorder(threadId: ThreadId, itemIds: [String]) async throws {
        try lock.withLock { state in
            let queue = state.items[threadId] ?? []
            let currentIds = queue.map(\.id)
            guard Set(itemIds) == Set(currentIds), itemIds.count == currentIds.count else {
                throw ThreadStoreError.invalidRequest(
                    "item_ids is not a permutation of the complete queue")
            }
            let byId = Dictionary(uniqueKeysWithValues: queue.map { ($0.id, $0) })
            state.items[threadId] = itemIds.compactMap { byId[$0] }
            bump(&state, threadId: threadId)
        }
    }

    private func bump(_ state: inout State, threadId: ThreadId) {
        state.revision += 1
        state.threadRevisions[threadId] = state.revision
    }
}

/// Adapts the local state runtime to the shared queue-storage interface.
///
/// GRDB-backed `SqliteQueueStore` is not ported yet; this type keeps the
/// constructor and throws `unsupported` until that lands.
public final class LocalQueueStore: QueueStore, @unchecked Sendable {
    private let stateDb: StateDbHandle

    public init(stateDb: StateDbHandle) {
        self.stateDb = stateDb
    }

    public func changeVersion() async throws -> Int64 {
        _ = stateDb
        throw ThreadStoreError.unsupported(operation: "queue/change_version")
    }

    public func changesSince(revision: Int64, threadIds: [ThreadId]) async throws -> [(ThreadId, Int64)] {
        _ = revision
        _ = threadIds
        throw ThreadStoreError.unsupported(operation: "queue/changes_since")
    }

    public func enqueue(threadId: ThreadId, payload: String) async throws -> QueuedUserSubmissionRecord {
        _ = threadId
        _ = payload
        throw ThreadStoreError.unsupported(operation: "queue/enqueue")
    }

    public func listPage(
        threadId: ThreadId,
        offset: Int,
        limit: Int
    ) async throws -> [QueuedUserSubmissionRecord] {
        _ = threadId
        _ = offset
        _ = limit
        throw ThreadStoreError.unsupported(operation: "queue/list_page")
    }

    public func update(
        threadId: ThreadId,
        itemId: String,
        payload: String
    ) async throws -> QueuedUserSubmissionRecord? {
        _ = threadId
        _ = itemId
        _ = payload
        throw ThreadStoreError.unsupported(operation: "queue/update")
    }

    public func delete(threadId: ThreadId, itemId: String) async throws -> Bool {
        _ = threadId
        _ = itemId
        throw ThreadStoreError.unsupported(operation: "queue/delete")
    }

    public func reorder(threadId: ThreadId, itemIds: [String]) async throws {
        _ = threadId
        _ = itemIds
        throw ThreadStoreError.unsupported(operation: "queue/reorder")
    }
}
