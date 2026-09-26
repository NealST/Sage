//
//  archive_thread.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/archive_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  File-move semantics: `sessions/` → `archived_sessions/`, restore on
//  failure via `restoreRolloutMoves`. Rejects a live recorder. Skips
//  `live_writer_locks` reservation. State-DB `mark_archived` is not
//  wired; a non-nil `stateDb()` restores moves and throws `internal`.
//

import CodexProtocol
import CodexRollout
import Foundation
import os

private let logger = Logger(subsystem: "CodexThreadStore", category: "archive_thread")

func archiveLocalThread(store: LocalThreadStore, params: ArchiveThreadParams) throws {
    _ = try archiveLocalThreads(
        store: store,
        params: ArchiveThreadsParams(threadIds: [params.threadId], writerLockThreadIds: [])
    )
}

func archiveLocalThreads(
    store: LocalThreadStore,
    params: ArchiveThreadsParams
) throws -> [ThreadId] {
    let threadIds = params.threadIds
    if threadIds.isEmpty {
        return []
    }

    var lockThreadIds = params.writerLockThreadIds
    lockThreadIds.append(contentsOf: threadIds)
    lockThreadIds.sort { $0.description < $1.description }
    var deduped: [ThreadId] = []
    for threadId in lockThreadIds {
        if deduped.last != threadId {
            deduped.append(threadId)
        }
    }
    lockThreadIds = deduped

    for threadId in lockThreadIds {
        try store.rejectIfLiveWriter(threadId)
    }
    let writerGuards = try store.acquireWriterLocks(lockThreadIds)
    defer { _ = writerGuards }

    let referenceIndex: RolloutReferenceIndex
    do {
        referenceIndex = try RolloutReferenceIndex.scanUnarchivedThreads(
            codexHome: store.config.codexHome,
            threadIds: threadIds
        )
    } catch {
        throw ThreadStoreError.internal(
            "failed to scan thread rollout files: \(error)")
    }

    let parentThreadId = threadIds[0]
    var archivedThreadIds: [ThreadId] = []
    for threadId in threadIds {
        let rolloutPaths = ownedRolloutPathsFromIndex(referenceIndex, threadId: threadId)
        do {
            try archiveThreadWithPaths(store: store, threadId: threadId, rolloutPaths: rolloutPaths)
            archivedThreadIds.append(threadId)
        } catch {
            if archivedThreadIds.isEmpty {
                throw error
            }
            logger.warning(
                "failed to archive spawned descendant thread \(threadId.description, privacy: .public) while archiving \(parentThreadId.description, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
    return archivedThreadIds
}

private func archiveThreadWithPaths(
    store: LocalThreadStore,
    threadId: ThreadId,
    rolloutPaths: [String]
) throws {
    var rolloutPaths = rolloutPaths
    guard let selectedRolloutPath = try resolveCurrent(store: store, threadId: threadId)?.path else {
        throw ThreadStoreError.invalidRequest(
            "no rollout found for thread id \(threadId)")
    }

    let archiveFolder = (store.config.codexHome as NSString)
        .appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)
    do {
        try FileManager.default.createDirectory(
            atPath: archiveFolder, withIntermediateDirectories: true)
    } catch {
        throw ThreadStoreError.internal("failed to archive thread: \(error)")
    }

    if !rolloutPaths.contains(selectedRolloutPath) {
        rolloutPaths.append(selectedRolloutPath)
    }

    var archivedPath: String?
    var rolloutMoves: [(String, String)] = []
    let sessionsRoot = (store.config.codexHome as NSString)
        .appendingPathComponent(SESSIONS_SUBDIR)
    for rolloutPath in rolloutPaths {
        if rolloutPathIsArchived(codexHome: store.config.codexHome, path: rolloutPath) {
            continue
        }
        let canonicalRolloutPath = try scopedRolloutPath(
            root: sessionsRoot,
            rolloutPath: rolloutPath,
            rootName: "sessions"
        )
        let fileName = try validatedRolloutFileName(
            rolloutPath: canonicalRolloutPath, displayPath: rolloutPath
        )
        let destination = (archiveFolder as NSString).appendingPathComponent(fileName)
        if rolloutPath == selectedRolloutPath {
            archivedPath = destination
        }
        if !rolloutMoves.contains(where: { $0.0 == canonicalRolloutPath }) {
            rolloutMoves.append((canonicalRolloutPath, destination))
        }
    }
    guard let archivedPath else {
        throw ThreadStoreError.internal(
            "failed to archive selected rollout for thread \(threadId)")
    }
    _ = archivedPath

    for (index, move) in rolloutMoves.enumerated() {
        do {
            try FileManager.default.moveItem(atPath: move.0, toPath: move.1)
        } catch let moveError {
            do {
                try restoreRolloutMoves(Array(rolloutMoves[..<index]))
            } catch let restoreError {
                throw ThreadStoreError.internal(
                    "failed to archive thread: \(moveError); failed to restore moved rollouts: \(restoreError)"
                )
            }
            throw ThreadStoreError.internal("failed to archive thread: \(moveError)")
        }
    }

    if store.stateDb() != nil {
        do {
            try restoreRolloutMoves(rolloutMoves)
        } catch {
            throw ThreadStoreError.internal(
                "failed to update archived thread metadata: SQLite state DB is not wired; failed to restore moved rollouts: \(error)"
            )
        }
        throw ThreadStoreError.internal(
            "failed to update archived thread metadata: SQLite state DB is not wired")
    }
}
