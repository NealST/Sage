//
//  unarchive_thread.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/unarchive_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Reverse of archive: `archived_sessions/` → `sessions/YYYY/MM/DD/`.
//  Rejects a live recorder. Skips `live_writer_locks` reservation.
//  State-DB `mark_unarchived` is not wired; a non-nil `stateDb()`
//  restores moves and throws `internal`. Returns `readLocalThread`.
//

import CodexProtocol
import CodexRollout
import Foundation

func unarchiveLocalThread(
    store: LocalThreadStore,
    params: ArchiveThreadParams
) throws -> StoredThread {
    let threadId = params.threadId
    try store.rejectIfLiveWriter(threadId)
    let writerLock = try store.acquireWriterLock(threadId)
    defer { _ = writerLock }

    guard let selectedArchivedPath = try resolveCurrentIncludingArchived(
        store: store, threadId: threadId
    ).flatMap({ resolved -> String? in
        resolved.location == .archived ? resolved.path : nil
    }) else {
        throw ThreadStoreError.invalidRequest(
            "no archived rollout found for thread id \(threadId)")
    }

    var rolloutPaths = ownedRolloutPaths(store: store, threadId: threadId)
    if !rolloutPaths.contains(selectedArchivedPath) {
        rolloutPaths.append(selectedArchivedPath)
    }

    var restoredPath: String?
    var rolloutMoves: [(String, String)] = []
    let archivedRoot = (store.config.codexHome as NSString)
        .appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)
    for rolloutPath in rolloutPaths {
        if !rolloutPathIsArchived(codexHome: store.config.codexHome, path: rolloutPath) {
            continue
        }
        let canonicalArchivedPath = try scopedRolloutPath(
            root: archivedRoot,
            rolloutPath: rolloutPath,
            rootName: "archived"
        )
        let fileName = try validatedRolloutFileName(
            rolloutPath: canonicalArchivedPath, displayPath: rolloutPath
        )
        guard let (year, month, day) = rolloutDateParts(fileName) else {
            throw ThreadStoreError.invalidRequest(
                "rollout path `\(rolloutPath)` missing filename timestamp")
        }
        let destDir = ((((store.config.codexHome as NSString)
            .appendingPathComponent(SESSIONS_SUBDIR) as NSString)
            .appendingPathComponent(year) as NSString)
            .appendingPathComponent(month) as NSString)
            .appendingPathComponent(day)
        do {
            try FileManager.default.createDirectory(
                atPath: destDir, withIntermediateDirectories: true)
        } catch {
            throw ThreadStoreError.internal("failed to unarchive thread: \(error)")
        }
        let destination = (destDir as NSString).appendingPathComponent(fileName)
        if rolloutPath == selectedArchivedPath {
            restoredPath = destination
        }
        if !rolloutMoves.contains(where: { $0.0 == canonicalArchivedPath }) {
            rolloutMoves.append((canonicalArchivedPath, destination))
        }
    }
    guard let restoredPath else {
        throw ThreadStoreError.internal(
            "failed to unarchive selected rollout for thread \(threadId)")
    }

    for (index, move) in rolloutMoves.enumerated() {
        do {
            try FileManager.default.moveItem(atPath: move.0, toPath: move.1)
        } catch let moveError {
            do {
                try restoreRolloutMoves(Array(rolloutMoves[..<index]))
            } catch let restoreError {
                throw ThreadStoreError.internal(
                    "failed to unarchive thread: \(moveError); failed to restore moved rollouts: \(restoreError)"
                )
            }
            throw ThreadStoreError.internal("failed to unarchive thread: \(moveError)")
        }
    }
    do {
        try touchModifiedTime(restoredPath)
    } catch let touchError {
        do {
            try restoreRolloutMoves(rolloutMoves)
        } catch let restoreError {
            throw ThreadStoreError.internal(
                "failed to update unarchived thread timestamp: \(touchError); failed to restore moved rollouts: \(restoreError)"
            )
        }
        throw ThreadStoreError.internal(
            "failed to update unarchived thread timestamp: \(touchError)")
    }

    if store.stateDb() != nil {
        do {
            try restoreRolloutMoves(rolloutMoves)
        } catch {
            throw ThreadStoreError.internal(
                "failed to update unarchived thread metadata: SQLite state DB is not wired; failed to restore moved rollouts: \(error)"
            )
        }
        throw ThreadStoreError.internal(
            "failed to update unarchived thread metadata: SQLite state DB is not wired")
    }

    return try readLocalThread(
        store: store,
        params: ReadThreadParams(
            threadId: threadId,
            includeArchived: false,
            includeHistory: false
        )
    )
}
