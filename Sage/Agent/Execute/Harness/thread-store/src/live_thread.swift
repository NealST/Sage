//
//  live_thread.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/live_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Tokio Drop spawn is omitted; `discard()` is explicit. Paginated
//  resume does not downcast into a state DB (`as_any` was not ported).
//  `RolloutPersistenceTelemetry` is a local no-op until CodexRollout
//  grows the type.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation
import os

/// Local no-op stand-in for `codex_rollout::RolloutPersistenceTelemetry`.
struct RolloutPersistenceTelemetry: Sendable {
    init(_ threadId: ThreadId) {
        _ = threadId
    }

    func isEnabled() -> Bool { false }

    func recordBatch(_ rawItems: [RolloutItem], _ measurement: Void) {
        _ = rawItems
        _ = measurement
    }
}

/// Handle for an active thread's persistence lifecycle.
public final class LiveThread: @unchecked Sendable {
    public let threadId: ThreadId
    private let historyMode: ThreadHistoryMode
    private let threadStore: any ThreadStore
    private let metadataSync = OSAllocatedUnfairLock<ThreadMetadataSync?>(initialState: nil)
    private let persistenceTelemetry: RolloutPersistenceTelemetry

    private init(
        threadId: ThreadId,
        historyMode: ThreadHistoryMode,
        threadStore: any ThreadStore,
        metadataSync: ThreadMetadataSync
    ) {
        self.threadId = threadId
        self.historyMode = historyMode
        self.threadStore = threadStore
        self.persistenceTelemetry = RolloutPersistenceTelemetry(threadId)
        self.metadataSync.withLock { $0 = metadataSync }
    }

    public static func create(
        threadStore: any ThreadStore,
        params: CreateThreadParams
    ) async throws -> LiveThread {
        let threadId = params.threadId
        let historyMode = params.historyMode
        let metadataSync = await ThreadMetadataSync.forCreate(params)
        try await threadStore.createThread(params)
        return LiveThread(
            threadId: threadId,
            historyMode: historyMode,
            threadStore: threadStore,
            metadataSync: metadataSync
        )
    }

    /// Create a child thread with inherited model context already durable.
    public static func createWithInheritedModelContext(
        threadStore: any ThreadStore,
        params: CreateThreadParams,
        inheritedModelContext: [RolloutItem],
        guard initGuard: LiveThreadInitGuard
    ) async throws -> LiveThread {
        var params = params
        let persistedPrefixItemCount = persistedRolloutItems(
            inheritedModelContext, historyMode: params.historyMode
        ).count
        guard persistedPrefixItemCount < Int.max,
              let start = UInt64(exactly: persistedPrefixItemCount + 1)
        else {
            throw ThreadStoreError.internal("inherited model context is too large")
        }
        params.subagentHistoryStartOrdinal = start
        let createParams = params
        let liveThread = try await initGuard.acquire {
            try await LiveThread.create(threadStore: threadStore, params: createParams)
        }
        _ = try await liveThread.persistAppendedItems(inheritedModelContext)
        return liveThread
    }

    public static func resume(
        threadStore: any ThreadStore,
        historyMode: ThreadHistoryMode,
        params: ResumeThreadParams
    ) async throws -> LiveThread {
        let threadId = params.threadId
        let shouldLoadHistory = params.history == nil
        let includeArchived = params.includeArchived
        var metadataSync = ThreadMetadataSync.forResume(params, metadata: nil)
        try await threadStore.resumeThread(params)
        if shouldLoadHistory {
            do {
                let history = try await threadStore.loadHistory(
                    LoadThreadHistoryParams(threadId: threadId, includeArchived: includeArchived)
                )
                metadataSync.recordResumeHistory(history.items)
            } catch {
                do {
                    try await threadStore.discardThread(threadId: threadId)
                } catch {
                    // Best-effort cleanup after a failed resume history load.
                }
                throw error
            }
        }
        return LiveThread(
            threadId: threadId,
            historyMode: historyMode,
            threadStore: threadStore,
            metadataSync: metadataSync
        )
    }

    public func appendItems(_ rawItems: [RolloutItem]) async throws {
        let items = try await persistAppendedItems(rawItems)
        if items.isEmpty { return }
        let update = metadataSync.withLock { sync -> PendingThreadMetadataPatch? in
            guard var current = sync else { return nil }
            let result = current.observeAppendedItems(items)
            sync = current
            return result
        }
        if let update {
            try await threadStore.recordThreadMetadata(
                UpdateThreadMetadataParams(
                    threadId: threadId,
                    patch: update.patch,
                    includeArchived: true
                )
            )
            metadataSync.withLock { sync in
                sync?.markPendingUpdateApplied(update)
            }
        }
    }

    private func persistAppendedItems(_ rawItems: [RolloutItem]) async throws -> [RolloutItem] {
        if rawItems.isEmpty { return [] }
        let items = persistedRolloutItems(rawItems, historyMode: historyMode)
        try await threadStore.appendItems(
            AppendThreadItemsParams(threadId: threadId, items: rawItems)
        )
        if persistenceTelemetry.isEnabled() {
            persistenceTelemetry.recordBatch(rawItems, ())
        }
        return items
    }

    public func persist(_ context: PersistContext) async throws {
        if context.allowsBackgroundPersistence() {
            let update = metadataSync.withLock { $0?.takePendingUpdateForExistingHistory() }
            try await applyPendingMetadataUpdate(update, context: context)
        }
        try await threadStore.persistThread(threadId: threadId, context: context)
        let update = metadataSync.withLock { $0?.takePendingUpdate() }
        try await applyPendingMetadataUpdate(update, context: context)
    }

    public func flush() async throws {
        try await threadStore.flushThread(threadId: threadId)
        try await flushPendingMetadataUpdateForExistingHistory()
    }

    public func shutdown() async throws {
        var metadataError: Error?
        do {
            try await flushPendingMetadataUpdateForExistingHistory()
        } catch {
            metadataError = error
        }
        do {
            try await threadStore.shutdownThread(threadId: threadId)
        } catch {
            if let metadataError {
                throw ThreadStoreError.internal(
                    "thread metadata update failed: \(metadataError); thread shutdown failed: \(error)"
                )
            }
            throw error
        }
        if let metadataError { throw metadataError }
    }

    public func discard() async throws {
        try await threadStore.discardThread(threadId: threadId)
    }

    public func loadHistory(includeArchived: Bool) async throws -> StoredThreadHistory {
        try await threadStore.loadHistory(
            LoadThreadHistoryParams(threadId: threadId, includeArchived: includeArchived)
        )
    }

    public func readThread(includeArchived: Bool, includeHistory: Bool) async throws -> StoredThread {
        try await threadStore.readThread(
            ReadThreadParams(
                threadId: threadId,
                includeArchived: includeArchived,
                includeHistory: includeHistory
            )
        )
    }

    public func updateMemoryMode(_ mode: ThreadMemoryMode, includeArchived: Bool) async throws {
        try await flushPendingMetadataUpdate()
        _ = try await threadStore.updateThreadMetadata(
            UpdateThreadMetadataParams(
                threadId: threadId,
                patch: ThreadMetadataPatch(memoryMode: mode),
                includeArchived: includeArchived
            )
        )
    }

    /// Updates metadata while preserving this API's materialized-thread contract.
    public func updateMetadata(
        _ patch: ThreadMetadataPatch,
        includeArchived: Bool
    ) async throws -> StoredThread {
        try await flushPendingMetadataUpdate()
        if let updated = try await threadStore.updateThreadMetadata(
            UpdateThreadMetadataParams(
                threadId: threadId,
                patch: patch,
                includeArchived: includeArchived
            )
        ) {
            return updated
        }
        return try await readThread(includeArchived: includeArchived, includeHistory: false)
    }

    /// Returns the live local rollout path for legacy local-only callers.
    public func localRolloutPath() async throws -> String? {
        guard let localStore = threadStore as? LocalThreadStore else {
            return nil
        }
        return try await localStore.liveRolloutPath(threadId)
    }

    private func flushPendingMetadataUpdate() async throws {
        let update = metadataSync.withLock { $0?.takePendingUpdate() }
        try await applyPendingMetadataUpdate(update, context: .standard)
    }

    private func flushPendingMetadataUpdateForExistingHistory() async throws {
        let update = metadataSync.withLock { $0?.takePendingUpdateForExistingHistory() }
        try await applyPendingMetadataUpdate(update, context: .standard)
    }

    private func applyPendingMetadataUpdate(
        _ update: PendingThreadMetadataPatch?,
        context: PersistContext
    ) async throws {
        guard let update else { return }
        let params = UpdateThreadMetadataParams(
            threadId: threadId,
            patch: update.patch,
            includeArchived: true
        )
        if context == .standard {
            _ = try await threadStore.updateThreadMetadata(params)
        } else {
            try await threadStore.recordThreadMetadata(params)
        }
        metadataSync.withLock { $0?.markPendingUpdateApplied(update) }
    }
}

/// Owns persistence acquisition and its live thread while initialization is still fallible.
///
/// Tokio `Drop` spawn is omitted; call `discard()` explicitly if init fails.
public final class LiveThreadInitGuard: @unchecked Sendable {
    private var liveThread: LiveThread?
    private var acquiring: Task<LiveThread, Error>?

    public init(liveThread: LiveThread? = nil) {
        self.liveThread = liveThread
    }

    /// Retains the operation even if the caller stops waiting.
    public func acquire(
        _ acquisition: @escaping @Sendable () async throws -> LiveThread
    ) async throws -> LiveThread {
        guard liveThread == nil, acquiring == nil else {
            throw ThreadStoreError.internal("persistence acquisition already in progress")
        }
        let task = Task { try await acquisition() }
        acquiring = task
        do {
            let result = try await task.value
            acquiring = nil
            liveThread = result
            return result
        } catch {
            acquiring = nil
            throw error
        }
    }

    public func asLiveThread() -> LiveThread? {
        liveThread
    }

    public func commit() {
        liveThread = nil
    }

    public func discard() async {
        if let acquiring {
            _ = try? await acquiring.value
            self.acquiring = nil
        }
        guard let liveThread else { return }
        self.liveThread = nil
        do {
            try await liveThread.discard()
        } catch {
            // Failed session init should not surface discard errors.
        }
    }
}
