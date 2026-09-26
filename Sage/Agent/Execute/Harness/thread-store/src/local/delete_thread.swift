//
//  delete_thread.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/delete_thread.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Durable JSONL delete (sessions + archived). Rejects a live writer.
//  Skips `live_writer_locks` reservation, state-DB row delete, memories
//  / attachments SQL, and materialized thread-history. Fork-history
//  reference checks use `RolloutReferenceIndex`. Test-only helpers are
//  not ported.
//

import CodexProtocol
import CodexRollout
import Foundation

private struct ThreadRollouts {
    var threadId: ThreadId
    var rolloutIds: Set<ThreadId>
    var paths: [String]

    static func fromIndex(_ index: RolloutReferenceIndex, threadId: ThreadId) -> ThreadRollouts {
        var rolloutIds = Set<ThreadId>()
        var paths: [String] = []
        for (rolloutId, path) in index.rolloutsForThread(threadId) {
            rolloutIds.insert(rolloutId)
            paths.append(path)
        }
        return ThreadRollouts(threadId: threadId, rolloutIds: rolloutIds, paths: paths)
    }

    mutating func addPath(_ path: String) {
        if let rolloutId = rolloutIdFromPath(path) {
            rolloutIds.insert(rolloutId)
        }
        if !paths.contains(path) {
            paths.append(path)
        }
    }
}

func deleteLocalThread(store: LocalThreadStore, params: DeleteThreadParams) throws {
    let threadId = params.threadId
    try store.rejectIfLiveWriter(threadId)
    let writerGuards = try store.acquireWriterLocks([threadId])
    defer { _ = writerGuards }

    let referenceIndex = try scanReferenceIndex(store)
    let threadRollouts = ThreadRollouts.fromIndex(referenceIndex, threadId: threadId)
    try ensureNoExternalReferences(referenceIndex, [threadRollouts])

    let foundRollout: Bool
    do {
        try deleteThreadAfterReferenceCheck(store: store, threadRollouts: threadRollouts)
        foundRollout = true
    } catch let error as ThreadStoreError {
        if case .threadNotFound = error {
            foundRollout = false
        } else {
            throw error
        }
    }
    if foundRollout {
        return
    }
    throw ThreadStoreError.threadNotFound(threadId.description)
}

func deleteLocalThreads(store: LocalThreadStore, params: DeleteThreadsParams) throws {
    let threadIds = params.threadIds
    if threadIds.isEmpty {
        return
    }

    var lockThreadIds = threadIds
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

    let referenceIndex = try scanReferenceIndex(store)
    let threadRollouts = threadIds.map { ThreadRollouts.fromIndex(referenceIndex, threadId: $0) }
    try ensureNoExternalReferences(referenceIndex, threadRollouts)

    for rollouts in threadRollouts {
        do {
            try deleteThreadAfterReferenceCheck(store: store, threadRollouts: rollouts)
        } catch let error as ThreadStoreError {
            if case .threadNotFound = error { continue }
            throw error
        }
    }
}

private func scanReferenceIndex(_ store: LocalThreadStore) throws -> RolloutReferenceIndex {
    do {
        return try RolloutReferenceIndex.scan(codexHome: store.config.codexHome)
    } catch {
        throw ThreadStoreError.internal(
            "failed to scan fork history references: \(error)")
    }
}

private func referencedThreadError(_ threadId: ThreadId) -> ThreadStoreError {
    ThreadStoreError.invalidRequest(
        "cannot delete thread \(threadId): forked history still references it")
}

private func ensureNoExternalReferences(
    _ referenceIndex: RolloutReferenceIndex,
    _ threadRollouts: [ThreadRollouts]
) throws {
    var deletionRolloutIds = Set<ThreadId>()
    for rollouts in threadRollouts {
        deletionRolloutIds.formUnion(rollouts.rolloutIds)
    }
    var internalReferenceCounts: [ThreadId: Int] = [:]
    for sourceRolloutId in deletionRolloutIds {
        if let historyBase = referenceIndex.historyBase(sourceRolloutId),
           historyBase.threadId != sourceRolloutId,
           deletionRolloutIds.contains(historyBase.threadId)
        {
            internalReferenceCounts[historyBase.threadId, default: 0] += 1
        }
    }
    for rollouts in threadRollouts {
        let referenced = rollouts.rolloutIds.contains { rolloutId in
            let internalCount = internalReferenceCounts[rolloutId] ?? 0
            return referenceIndex.referenceCount(rolloutId) > internalCount
        }
        if referenced {
            throw referencedThreadError(rollouts.threadId)
        }
    }
}

private func deleteThreadAfterReferenceCheck(
    store: LocalThreadStore,
    threadRollouts: ThreadRollouts
) throws {
    var threadRollouts = threadRollouts
    let threadId = threadRollouts.threadId
    let threadIdStr = threadId.description

    do {
        if let path = try findThreadPathByIdStr(
            codexHome: store.config.codexHome, idStr: threadIdStr
        ) {
            threadRollouts.addPath(path)
        }
    } catch {
        throw ThreadStoreError.invalidRequest(
            "failed to locate thread id \(threadId): \(error)")
    }
    do {
        if let path = try findArchivedThreadPathByIdStr(
            codexHome: store.config.codexHome, idStr: threadIdStr
        ) {
            threadRollouts.addPath(path)
        }
    } catch {
        throw ThreadStoreError.invalidRequest(
            "failed to locate archived thread id \(threadId): \(error)")
    }

    let foundRolloutPath = !threadRollouts.paths.isEmpty
    for rolloutPath in threadRollouts.paths {
        _ = try deleteRolloutFile(store: store, rolloutPath: rolloutPath)
    }
    do {
        try removeThreadNameEntries(codexHome: store.config.codexHome, threadId: threadId)
    } catch {
        throw ThreadStoreError.internal(
            "failed to delete thread name index entries for \(threadId): \(error)")
    }

    if !foundRolloutPath {
        throw ThreadStoreError.threadNotFound(threadId.description)
    }
}

private func deleteRolloutFile(store: LocalThreadStore, rolloutPath: String) throws -> Bool {
    let plainPath = plainRolloutPath(rolloutPath)
    let compressedPath = compressedRolloutPath(plainPath)
    let deletedPlain = try deleteRolloutPath(store: store, rolloutPath: plainPath)
    let deletedCompressed = try deleteRolloutPath(store: store, rolloutPath: compressedPath)
    return deletedPlain || deletedCompressed
}

private func deleteRolloutPath(store: LocalThreadStore, rolloutPath: String) throws -> Bool {
    let canonicalRolloutPath: String
    do {
        canonicalRolloutPath = try scopedRolloutPath(
            root: (store.config.codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR),
            rolloutPath: rolloutPath,
            rootName: "sessions"
        )
    } catch {
        do {
            canonicalRolloutPath = try scopedRolloutPath(
                root: (store.config.codexHome as NSString)
                    .appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR),
                rolloutPath: rolloutPath,
                rootName: "archived sessions"
            )
        } catch let archivedError {
            if !FileManager.default.fileExists(atPath: rolloutPath) {
                canonicalRolloutPath = rolloutPath
            } else {
                throw archivedError
            }
        }
    }
    _ = try validatedRolloutFileName(
        rolloutPath: canonicalRolloutPath, displayPath: rolloutPath
    )
    do {
        try FileManager.default.removeItem(atPath: canonicalRolloutPath)
        return true
    } catch {
        if isNotFoundError(error) {
            return false
        }
        throw ThreadStoreError.internal(
            "failed to delete rollout file `\(canonicalRolloutPath)`: \(error)")
    }
}

private func isNotFoundError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain
        && (nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError)
    {
        return true
    }
    if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT) {
        return true
    }
    return false
}
