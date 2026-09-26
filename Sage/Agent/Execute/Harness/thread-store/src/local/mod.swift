//
//  mod.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Local JSONL store via `RolloutRecorder` + FileManager. create / resume /
//  append / persist / flush / shutdown / discard / read / list / archive /
//  unarchive / search / delete are a working subset. Pending-metadata is an
//  in-process map. SQLite, rollout_migration, and live-writer locks are
//  omitted; other ThreadStore methods throw `unsupported`.
//  Paginated history lists (`listTurns` / `listItems` / `listTimeline` /
//  `searchThreadOccurrences`) are wired and throw until GRDB.
//  `migrateRollouts` dry-run inspects JSONL; Apply throws until GRDB.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import CodexState
import Foundation
import os

/// Process-scoped configuration for local thread storage.
public struct LocalThreadStoreConfig: Equatable, Sendable {
    public var codexHome: String
    public var sqlite: SqliteConfig
    /// Provider used only when older local metadata does not contain one.
    public var defaultModelProviderId: String

    public init(
        codexHome: String,
        sqlite: SqliteConfig = SqliteConfig(),
        defaultModelProviderId: String
    ) {
        self.codexHome = codexHome
        self.sqlite = sqlite
        self.defaultModelProviderId = defaultModelProviderId
    }

    public static func fromView(_ view: any RolloutConfigView) -> LocalThreadStoreConfig {
        LocalThreadStoreConfig(
            codexHome: view.codexHome,
            sqlite: view.sqliteConfig,
            defaultModelProviderId: view.modelProviderId
        )
    }
}

private struct LiveRecorderEntry {
    var recorder: RolloutRecorder
    var rolloutId: ThreadId
    var historyMode: ThreadHistoryMode
    var writerLock: WriterLockGuard
}

/// Local filesystem-backed implementation of `ThreadStore`.
///
/// Rollout JSONL files are the durable replay format. The SQLite state DB
/// is not wired yet; list/read walk JSONL via CodexRollout.
public final class LocalThreadStore: ThreadStore, @unchecked Sendable {
    public let config: LocalThreadStoreConfig
    private let liveRecorders = OSAllocatedUnfairLock<[ThreadId: LiveRecorderEntry]>(initialState: [:])
    let pendingThreadMetadata = PendingThreadMetadataRegistry()
    private let writerLockCoordinator: WriterLockCoordinator
    private let stateDbHandle: StateDbHandle?

    public init(config: LocalThreadStoreConfig, stateDb: StateDbHandle? = nil) {
        self.config = config
        self.writerLockCoordinator = WriterLockCoordinator(codexHome: config.codexHome)
        self.stateDbHandle = stateDb
    }

    public func stateDb() -> StateDbHandle? {
        stateDbHandle
    }

    public func liveRolloutPath(_ threadId: ThreadId) async throws -> String {
        try liveRolloutPathSync(threadId)
    }

    func liveRolloutPathSync(_ threadId: ThreadId) throws -> String {
        try liveRecorders.withLock { recorders in
            guard let entry = recorders[threadId] else {
                throw ThreadStoreError.threadNotFound(threadId.description)
            }
            return entry.recorder.rolloutPath
        }
    }

    func liveWriterParts(
        _ threadId: ThreadId
    ) throws -> (RolloutRecorder, ThreadId, ThreadHistoryMode) {
        try liveRecorders.withLock { recorders in
            guard let entry = recorders[threadId] else {
                throw ThreadStoreError.threadNotFound(threadId.description)
            }
            return (entry.recorder, entry.rolloutId, entry.historyMode)
        }
    }

    public func defaultHistoryMode() -> ThreadHistoryMode { .paginated }

    public func stagePendingThreadMetadata(threadId: ThreadId, patch: ThreadMetadataPatch) async throws {
        if patch.rolloutPath != nil {
            throw ThreadStoreError.invalidRequest(
                "pending thread metadata cannot set rollout_path")
        }
        try pendingThreadMetadata.stage(threadId: threadId, patch: patch)
    }

    public func readPendingThreadMetadata(threadId: ThreadId) async throws -> ThreadMetadataPatch? {
        pendingThreadMetadata.read(threadId: threadId)
    }

    public func removePendingThreadMetadata(threadId: ThreadId) async throws {
        pendingThreadMetadata.remove(threadId: threadId)
    }

    public func createThread(_ params: CreateThreadParams) async throws {
        try ensureLiveRecorderAbsent(params.threadId)
        let writerLock = try acquireWriterLock(params.threadId)
        let recorder: RolloutRecorder
        do {
            recorder = try createLocalThreadRecorder(store: self, params: params)
        } catch {
            _ = writerLock
            throw error
        }
        try insertLiveRecorder(
            threadId: params.threadId,
            recorder: recorder,
            rolloutId: params.threadId,
            historyMode: params.historyMode,
            writerLock: writerLock
        )
    }

    public func resumeThread(_ params: ResumeThreadParams) async throws {
        try ensureLiveRecorderAbsent(params.threadId)
        let writerLock = try acquireWriterLock(params.threadId)
        let historyMode: ThreadHistoryMode
        if let history = params.history {
            historyMode = canonicalHistoryModeFromRolloutItems(history)
        } else if let rolloutPath = params.rolloutPath {
            historyMode = try readLocalThreadByRolloutPath(
                store: self,
                rolloutPath: rolloutPath,
                includeArchived: params.includeArchived,
                includeHistory: false
            ).historyMode
        } else {
            historyMode = try readLocalThread(
                store: self,
                params: ReadThreadParams(
                    threadId: params.threadId,
                    includeArchived: params.includeArchived,
                    includeHistory: false
                )
            ).historyMode
        }

        let rolloutPath: String
        if let explicit = params.rolloutPath {
            rolloutPath = explicit
        } else {
            let thread = try readLocalThread(
                store: self,
                params: ReadThreadParams(
                    threadId: params.threadId,
                    includeArchived: params.includeArchived,
                    includeHistory: params.history == nil
                )
            )
            guard let path = thread.rolloutPath else {
                throw ThreadStoreError.internal(
                    "thread \(params.threadId) does not have a rollout path")
            }
            rolloutPath = path
        }

        guard let cwd = params.metadata.cwd, !cwd.isEmpty else {
            throw ThreadStoreError.invalidRequest("local thread store requires a cwd")
        }
        let config = RolloutConfig(
            codexHome: self.config.codexHome,
            sqlite: self.config.sqlite,
            cwd: cwd,
            modelProviderId: params.metadata.modelProvider,
            generateMemories: params.metadata.memoryMode == .enabled
        )
        let recorder: RolloutRecorder
        do {
            recorder = try RolloutRecorder.create(config: config, params: .resume(path: rolloutPath))
        } catch {
            throw ThreadStoreError.internal(
                "failed to resume local thread recorder: \(error)")
        }
        let rolloutId = rolloutIdFromPath(rolloutPath) ?? params.threadId
        try insertLiveRecorder(
            threadId: params.threadId,
            recorder: recorder,
            rolloutId: rolloutId,
            historyMode: historyMode,
            writerLock: writerLock
        )
    }

    public func appendItems(_ params: AppendThreadItemsParams) async throws {
        try writeLive(threadId: params.threadId) { recorder, historyMode in
            let persisted = persistedRolloutItems(params.items, historyMode: historyMode)
            if persisted.isEmpty { return }
            try recorder.recordItems(persisted)
            try recorder.flush()
        }
    }

    public func persistThread(threadId: ThreadId, context: PersistContext) async throws {
        if context == .subagentSpawn { return }
        try writeLive(threadId: threadId) { recorder, _ in
            try recorder.persist()
        }
    }

    public func flushThread(threadId: ThreadId) async throws {
        try writeLive(threadId: threadId) { recorder, _ in
            try recorder.flush()
        }
    }

    public func shutdownThread(threadId: ThreadId) async throws {
        let path = try? liveRolloutPathSync(threadId)
        try writeLive(threadId: threadId) { recorder, _ in
            try recorder.shutdown()
        }
        _ = liveRecorders.withLock { $0.removeValue(forKey: threadId) }
        if let path, !FileManager.default.fileExists(atPath: path) {
            pendingThreadMetadata.remove(threadId: threadId)
        }
    }

    public func discardThread(threadId: ThreadId) async throws {
        pendingThreadMetadata.remove(threadId: threadId)
        let entry = liveRecorders.withLock { $0.removeValue(forKey: threadId) }
        guard let entry else {
            throw ThreadStoreError.threadNotFound(threadId.description)
        }
        let path = entry.recorder.rolloutPath
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        _ = entry.writerLock
    }

    public func loadHistory(_ params: LoadThreadHistoryParams) async throws -> StoredThreadHistory {
        try loadLocalHistory(store: self, params: params)
    }

    public func loadLatestModelContext(
        _ params: LoadThreadHistoryParams
    ) async throws -> StoredModelContext {
        try loadLatestLocalModelContext(store: self, params: params)
    }

    public func readThread(_ params: ReadThreadParams) async throws -> StoredThread {
        try readLocalThread(store: self, params: params)
    }

    public func readThreadByRolloutPath(
        _ params: ReadThreadByRolloutPathParams
    ) async throws -> StoredThread {
        try readLocalThreadByRolloutPath(
            store: self,
            rolloutPath: params.rolloutPath,
            includeArchived: params.includeArchived,
            includeHistory: params.includeHistory
        )
    }

    public func listThreads(_ params: ListThreadsParams) async throws -> ThreadPage {
        try listLocalThreads(store: self, params: params)
    }

    public func searchThreads(_ params: SearchThreadsParams) async throws -> ThreadSearchPage {
        try searchLocalThreads(store: self, params: params)
    }

    public func supportsPaginatedHistoryLists() -> Bool { false }

    public func listTurns(_ params: ListTurnsParams) async throws -> TurnPage {
        try listLocalTurns(store: self, params: params)
    }

    public func listItems(_ params: ListItemsParams) async throws -> ItemPage {
        try listLocalItems(store: self, params: params)
    }

    public func listTimeline(_ params: ListTimelineParams) async throws -> TimelinePage {
        try listLocalTimeline(store: self, params: params)
    }

    public func searchThreadOccurrences(
        _ params: SearchThreadOccurrencesParams
    ) async throws -> ThreadOccurrenceSearchPage {
        try searchLocalThreadOccurrences(store: self, params: params)
    }

    public func deleteThread(_ params: DeleteThreadParams) async throws {
        try deleteLocalThread(store: self, params: params)
    }

    public func deleteThreads(_ params: DeleteThreadsParams) async throws {
        try deleteLocalThreads(store: self, params: params)
    }

    public func updateThreadMetadata(
        _ params: UpdateThreadMetadataParams
    ) async throws -> StoredThread? {
        try updateLocalThreadMetadata(store: self, params: params)
    }

    public func archiveThread(_ params: ArchiveThreadParams) async throws {
        try archiveLocalThread(store: self, params: params)
    }

    public func archiveThreads(_ params: ArchiveThreadsParams) async throws -> [ThreadId] {
        try archiveLocalThreads(store: self, params: params)
    }

    public func unarchiveThread(_ params: ArchiveThreadParams) async throws -> StoredThread {
        try unarchiveLocalThread(store: self, params: params)
    }

    private func ensureLiveRecorderAbsent(_ threadId: ThreadId) throws {
        try liveRecorders.withLock { recorders in
            if recorders[threadId] != nil {
                throw ThreadStoreError.invalidRequest(
                    "thread \(threadId) already has a live local writer")
            }
        }
    }

    func rejectIfLiveWriter(_ threadId: ThreadId) throws {
        if (try? liveRolloutPathSync(threadId)) != nil {
            throw ThreadStoreError.conflict(
                message: "thread \(threadId) already has an active writer")
        }
    }

    func acquireWriterLocks(_ threadIds: [ThreadId]) throws -> [WriterLockGuard] {
        var guards: [WriterLockGuard] = []
        guards.reserveCapacity(threadIds.count)
        for threadId in threadIds {
            guards.append(try acquireWriterLock(threadId))
        }
        return guards
    }

    func acquireWriterLock(_ threadId: ThreadId) throws -> WriterLockGuard {
        do {
            return try writerLockCoordinator.acquire(threadId: threadId)
        } catch {
            let message = String(describing: error)
            if message.localizedCaseInsensitiveContains("would block")
                || message.localizedCaseInsensitiveContains("already has an active writer")
            {
                throw ThreadStoreError.conflict(message: message)
            }
            throw ThreadStoreError.internal(message)
        }
    }

    private func insertLiveRecorder(
        threadId: ThreadId,
        recorder: RolloutRecorder,
        rolloutId: ThreadId,
        historyMode: ThreadHistoryMode,
        writerLock: WriterLockGuard
    ) throws {
        try liveRecorders.withLock { recorders in
            if recorders[threadId] != nil {
                throw ThreadStoreError.invalidRequest(
                    "thread \(threadId) already has a live local writer")
            }
            recorders[threadId] = LiveRecorderEntry(
                recorder: recorder,
                rolloutId: rolloutId,
                historyMode: historyMode,
                writerLock: writerLock
            )
        }
    }

    private func writeLive(
        threadId: ThreadId,
        body: (RolloutRecorder, ThreadHistoryMode) throws -> Void
    ) throws {
        try liveRecorders.withLock { recorders in
            guard let entry = recorders[threadId] else {
                throw ThreadStoreError.threadNotFound(threadId.description)
            }
            try body(entry.recorder, entry.historyMode)
        }
    }
}
