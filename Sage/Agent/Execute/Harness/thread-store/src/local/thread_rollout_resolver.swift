//
//  thread_rollout_resolver.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/thread_rollout_resolver.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Resolves a thread ID to the rollout file it currently uses (live writer,
//  then active filesystem, then archived). SQLite selected-path lookup is
//  omitted until GRDB lands. `live_writer` is `liveRolloutPathSync`.
//

import CodexProtocol
import CodexRollout
import Foundation

/// One thread resolved to the concrete rollout file it currently uses.
///
/// For ordinary threads, `threadId` and `rolloutId` are the same. After
/// `thread/revert`, `threadId` stays stable while `rolloutId` identifies
/// the new immutable rollout file.
struct ResolvedThreadRollout: Equatable, Sendable {
    var threadId: ThreadId
    var rolloutId: ThreadId
    var path: String
    var location: RolloutLocation
}

enum RolloutLocation: Equatable, Sendable {
    case unarchived
    case archived
}

func resolveCurrent(
    store: LocalThreadStore,
    threadId: ThreadId
) throws -> ResolvedThreadRollout? {
    try resolve(store: store, threadId: threadId, scope: .excludeArchived)
}

func resolveCurrentIncludingArchived(
    store: LocalThreadStore,
    threadId: ThreadId
) throws -> ResolvedThreadRollout? {
    try resolve(store: store, threadId: threadId, scope: .includeArchived)
}

private enum LookupScope {
    case excludeArchived
    case includeArchived

    func accepts(_ location: RolloutLocation) -> Bool {
        switch self {
        case .excludeArchived: return location == .unarchived
        case .includeArchived: return true
        }
    }
}

/// Resolves a thread's selected rollout in this order:
///
/// 1. The live writer, when one exists.
/// 2. Filesystem fallback via `findThreadPathByIdStr`.
/// 3. Archived filesystem fallback, when requested.
///
/// SQLite's selected rollout path is skipped (state DB is not wired).
private func resolve(
    store: LocalThreadStore,
    threadId: ThreadId,
    scope: LookupScope
) throws -> ResolvedThreadRollout? {
    if let path = try? rolloutPath(store: store, threadId: threadId),
       let existing = existingRolloutPath(path),
       let resolved = try resolvePathInScope(
        store: store, threadId: threadId, path: existing, scope: scope
       )
    {
        return resolved
    }

    do {
        if let path = try findThreadPathByIdStr(
            codexHome: store.config.codexHome,
            idStr: threadId.description
        ), let resolved = try resolvePathInScope(
            store: store, threadId: threadId, path: path, scope: scope
        ) {
            return resolved
        }
    } catch let error as ThreadStoreError {
        throw error
    } catch {
        throw ThreadStoreError.invalidRequest(
            "failed to locate thread id \(threadId): \(error)")
    }

    if !scope.accepts(.archived) {
        return nil
    }

    let archived: String?
    do {
        archived = try findArchivedThreadPathByIdStr(
            codexHome: store.config.codexHome,
            idStr: threadId.description
        )
    } catch let error as ThreadStoreError {
        throw error
    } catch {
        throw ThreadStoreError.invalidRequest(
            "failed to locate archived thread id \(threadId): \(error)")
    }
    if let path = archived {
        return try resolvePathInScope(
            store: store, threadId: threadId, path: path, scope: scope
        )
    }
    return nil
}

private func resolvePathInScope(
    store: LocalThreadStore,
    threadId: ThreadId,
    path: String,
    scope: LookupScope
) throws -> ResolvedThreadRollout? {
    let location = locationForPath(store: store, path: path)
    if !scope.accepts(location) {
        return nil
    }
    return try resolvePath(threadId: threadId, path: path, location: location)
}

private func locationForPath(store: LocalThreadStore, path: String) -> RolloutLocation {
    if rolloutPathIsArchived(codexHome: store.config.codexHome, path: path) {
        return .archived
    }
    return .unarchived
}

private func resolvePath(
    threadId: ThreadId,
    path: String,
    location: RolloutLocation
) throws -> ResolvedThreadRollout {
    let rolloutId: ThreadId
    if let parsed = rolloutIdFromPath(path) {
        rolloutId = parsed
    } else {
        let historyMode: ThreadHistoryMode
        do {
            historyMode = try readSessionMetaLine(path: path).meta.historyMode
        } catch {
            throw ThreadStoreError.internal(
                "failed to read session metadata \(path): \(error)")
        }
        rolloutId = try rolloutIdFromPathOrLegacyThreadId(
            path: path, threadId: threadId, historyMode: historyMode
        )
    }
    return ResolvedThreadRollout(
        threadId: threadId,
        rolloutId: rolloutId,
        path: path,
        location: location
    )
}

/// Returns the immutable rollout ID for a path while preserving legacy noncanonical filenames.
func rolloutIdFromPathOrLegacyThreadId(
    path: String,
    threadId: ThreadId,
    historyMode: ThreadHistoryMode
) throws -> ThreadId {
    if let rolloutId = rolloutIdFromPath(path) {
        return rolloutId
    }
    if historyMode == .paginated {
        throw ThreadStoreError.invalidRequest(
            "paginated rollout path `\(path)` does not have a canonical rollout filename")
    }
    return threadId
}
