//
//  read_thread.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/read_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Working JSONL subset: resolve a path via live writer or filename walk,
//  then `readThreadItemFromRollout` + optional `RolloutRecorder.loadRolloutItems`.
//  SQLite metadata overlay and lineage resolver are omitted.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

func readLocalThread(
    store: LocalThreadStore,
    params: ReadThreadParams
) throws -> StoredThread {
    if let livePath = try? store.liveRolloutPathSync(params.threadId) {
        if !params.includeArchived,
           rolloutPathIsArchived(codexHome: store.config.codexHome, path: livePath)
        {
            throw ThreadStoreError.invalidRequest("thread \(params.threadId) is archived")
        }
        return try readLocalThreadByRolloutPath(
            store: store,
            rolloutPath: livePath,
            includeArchived: true,
            includeHistory: params.includeHistory
        )
    }

    let path: String?
    if params.includeArchived {
        path = try findThreadPathByIdStr(
            codexHome: store.config.codexHome,
            idStr: params.threadId.description
        ) ?? findArchivedThreadPathByIdStr(
            codexHome: store.config.codexHome,
            idStr: params.threadId.description
        )
    } else {
        path = try findThreadPathByIdStr(
            codexHome: store.config.codexHome,
            idStr: params.threadId.description
        )
    }
    guard let path else {
        throw ThreadStoreError.invalidRequest(
            "no rollout found for thread id \(params.threadId)")
    }
    let thread = try readLocalThreadByRolloutPath(
        store: store,
        rolloutPath: path,
        includeArchived: params.includeArchived,
        includeHistory: params.includeHistory
    )
    if !params.includeArchived && thread.archivedAt != nil {
        throw ThreadStoreError.invalidRequest("thread \(thread.threadId) is archived")
    }
    return thread
}

func readLocalThreadByRolloutPath(
    store: LocalThreadStore,
    rolloutPath: String,
    includeArchived: Bool,
    includeHistory: Bool
) throws -> StoredThread {
    guard FileManager.default.fileExists(atPath: rolloutPath) else {
        throw ThreadStoreError.invalidRequest("rollout path `\(rolloutPath)` does not exist")
    }
    let archived = rolloutPathIsArchived(codexHome: store.config.codexHome, path: rolloutPath)
    if !includeArchived && archived {
        throw ThreadStoreError.invalidRequest("rollout path `\(rolloutPath)` is archived")
    }
    guard let item = readThreadItemFromRollout(path: rolloutPath),
          var thread = storedThreadFromRolloutItem(
            item,
            archived: archived,
            defaultProvider: store.config.defaultModelProviderId
          )
    else {
        throw ThreadStoreError.internal(
            "failed to read rollout metadata from `\(rolloutPath)`")
    }
    if includeHistory {
        try rejectPaginatedHistoryMode(thread.historyMode)
        let loaded = try RolloutRecorder.loadRolloutItems(path: rolloutPath)
        thread.history = StoredThreadHistory(threadId: thread.threadId, items: loaded.items)
    }
    return thread
}

func loadHistoryItems(path: String) throws -> [RolloutItem] {
    do {
        return try RolloutRecorder.loadRolloutItems(path: path).items
    } catch {
        throw ThreadStoreError.internal(
            "failed to load thread history \(path): \(error)")
    }
}

func loadLocalHistory(
    store: LocalThreadStore,
    params: LoadThreadHistoryParams
) throws -> StoredThreadHistory {
    let thread = try readLocalThread(
        store: store,
        params: ReadThreadParams(
            threadId: params.threadId,
            includeArchived: params.includeArchived,
            includeHistory: true
        )
    )
    guard let history = thread.history else {
        throw ThreadStoreError.internal(
            "failed to load history for thread \(params.threadId)")
    }
    return history
}
