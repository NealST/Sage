//
//  live_writer.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/live_writer.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `live_writer_locks`, Tokio mutexes, SQLite history projection, otel
//  rollout-size metrics, and `thread_history_materialization` are not
//  ported. Public write ops and a process-local no-lock adapter sit
//  beside `LocalThreadStore`; create/resume/append/persist/flush stay
//  on the store. `sync_materialized_rollout_path` is omitted (no GRDB).
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

/// The rollout writer has three distinct lifecycle moments:
/// - `appendItems` is normal turn/event persistence and adds new rollout records.
/// - `persist` makes the thread durable before any turn items exist; locally this can write the
///   initial `SessionMeta`.
/// - `flush` writes any rollout records already queued in the recorder and ensures they are
///   durably persisted.
enum RolloutWriteOp {
    case appendItems([RolloutItem])
    case persist
    case flush
}

func createThread(store: LocalThreadStore, params: CreateThreadParams) async throws {
    try await store.createThread(params)
}

func resumeThread(store: LocalThreadStore, params: ResumeThreadParams) async throws {
    try await store.resumeThread(params)
}

func appendItems(store: LocalThreadStore, params: AppendThreadItemsParams) async throws {
    try await writeAndProject(
        store: store,
        threadId: params.threadId,
        writeOp: .appendItems(params.items)
    )
}

func persistThread(store: LocalThreadStore, threadId: ThreadId) async throws {
    try await writeAndProject(store: store, threadId: threadId, writeOp: .persist)
}

func flushThread(store: LocalThreadStore, threadId: ThreadId) async throws {
    try await writeAndProject(store: store, threadId: threadId, writeOp: .flush)
}

func shutdownThread(store: LocalThreadStore, threadId: ThreadId) async throws {
    try await store.shutdownThread(threadId: threadId)
}

func discardThread(store: LocalThreadStore, threadId: ThreadId) async throws {
    try await store.discardThread(threadId: threadId)
}

func rolloutPath(store: LocalThreadStore, threadId: ThreadId) throws -> String {
    try store.liveRolloutPathSync(threadId)
}

func liveWriterParts(
    store: LocalThreadStore,
    threadId: ThreadId
) throws -> (RolloutRecorder, ThreadId, ThreadHistoryMode) {
    try store.liveWriterParts(threadId)
}

func writeAndProject(
    store: LocalThreadStore,
    threadId: ThreadId,
    writeOp: RolloutWriteOp
) async throws {
    let (recorder, _, historyMode) = try liveWriterParts(store: store, threadId: threadId)
    let resolved: RolloutWriteOp
    switch writeOp {
    case .appendItems(let items):
        let persisted = persistedRolloutItems(items, historyMode: historyMode)
        if persisted.isEmpty { return }
        resolved = .appendItems(persisted)
    case .persist:
        resolved = .persist
    case .flush:
        resolved = .flush
    }
    try durableWrite(recorder: recorder, write: resolved)
}

func durableWrite(recorder: RolloutRecorder, write: RolloutWriteOp) throws {
    switch write {
    case .appendItems(let items):
        try recorder.recordItems(items)
        try recorder.flush()
    case .persist:
        try recorder.persist()
    case .flush:
        try recorder.flush()
    }
}

func threadStoreIoError(_ error: any Error) -> ThreadStoreError {
    .internal(String(describing: error))
}
