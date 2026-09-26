//
//  update_thread_metadata.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/update_thread_metadata.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  JSONL name index + empty-patch read. SQLite metadata / paginated title /
//  project_id / rollout rewrite wait for GRDB.
//
//  Working subset:
//  - Merge `pendingThreadMetadata` via registry read/remove (not a per-id mutex).
//  - `projectId` without `stateDb()` throws `unsupported("projects")`.
//  - Empty patch after merge returns `readLocalThread` (includeHistory false).
//  - `patch.name` is appended to `session_index.jsonl` (`ClearableField` clear → "").
//    Applied before paginated/SQLite throws so the index write is not dropped.
//  - Legacy `memory_mode` / `git_info` (requiresRolloutCompatibilityUpdate) rewrite
//    the first JSONL `session_meta` line via `readSessionMetaLine` + FileManager.
//    `live_writer_locks`, recorder append, and SQLite CAS are not used; git
//    unspecified fields are preserved from that first line instead of SQLite.
//  - Success returns `readLocalThread`, then overlays `findThreadNameById`.
//
//  Throws after the name-index write when that is all this port can do:
//  - Paginated history → `unsupported("paginated_threads")` (title/name live in SQLite).
//  - Observed / SQLite-only fields (title, preview, daybreak, …) →
//    `unsupported("update_thread_metadata")`.
//

import CodexProtocol
import CodexRollout
import Foundation

func updateLocalThreadMetadata(
    store: LocalThreadStore,
    params: UpdateThreadMetadataParams
) throws -> StoredThread {
    let threadId = params.threadId
    let pendingPatch = store.pendingThreadMetadata.read(threadId: threadId)
    var patch = params.patch
    if let stagedPatch = pendingPatch {
        var mergedPatch = stagedPatch
        mergedPatch.merge(patch)
        patch = mergedPatch
    }
    if patch.projectId != nil && store.stateDb() == nil {
        throw ThreadStoreError.unsupported(operation: "projects")
    }
    if patch.isEmpty() {
        return try readUpdatedLocalThread(
            store: store,
            threadId: threadId,
            includeArchived: params.includeArchived
        )
    }

    let stagedRequiresRolloutCompat =
        pendingPatch.map { $0.memoryMode != nil || $0.gitInfo != nil } ?? false
    let requiresRolloutCompat =
        stagedRequiresRolloutCompat || requiresRolloutCompatibilityUpdate(patch)
    let hasExplicitMetadata = patch.name != nil || requiresRolloutCompat
    let historyMode: ThreadHistoryMode?
    if hasExplicitMetadata {
        do {
            let (_, _, mode) = try liveWriterParts(store: store, threadId: threadId)
            historyMode = mode
        } catch let error as ThreadStoreError {
            if case .threadNotFound = error {
                historyMode = try readLocalThread(
                    store: store,
                    params: ReadThreadParams(
                        threadId: threadId,
                        includeArchived: params.includeArchived,
                        includeHistory: false
                    )
                ).historyMode
            } else {
                throw error
            }
        }
    } else {
        historyMode = nil
    }
    let paginated = historyMode == .paginated
    let needsRolloutCompat = requiresRolloutCompat || patch.name != nil

    // Name index before paginated / SQLite throws so a later unsupported error
    // cannot drop the durable session_index write.
    if let name = patch.name {
        do {
            try appendThreadName(
                codexHome: store.config.codexHome,
                threadId: threadId,
                name: name ?? ""
            )
        } catch {
            throw ThreadStoreError.internal(
                "failed to index thread name: \(error)")
        }
    }

    if paginated {
        throw ThreadStoreError.unsupported(operation: "paginated_threads")
    }

    // `sqliteWriteFailureShouldBlock` is true for git-only patches because Rust
    // CAS-merges unspecified fields from SQLite. This port merges those fields
    // from the first JSONL session_meta line, so git/memory-only patches
    // continue into the rewrite path instead of throwing here.
    if requiresSqliteMetadataPersist(patch) {
        throw ThreadStoreError.unsupported(operation: "update_thread_metadata")
    }

    if !needsRolloutCompat {
        if pendingPatch != nil {
            removePendingThreadMetadata(store: store, threadId: threadId)
        }
        return try readUpdatedLocalThread(
            store: store,
            threadId: threadId,
            includeArchived: params.includeArchived
        )
    }

    if (try? rolloutPath(store: store, threadId: threadId)) != nil {
        let (recorder, _, _) = try liveWriterParts(store: store, threadId: threadId)
        do {
            try recorder.persist()
        } catch {
            throw ThreadStoreError.internal(
                "failed to persist live rollout before metadata update: \(error)")
        }
    }

    let writerLock: WriterLockGuard?
    if patch.memoryMode != nil || patch.gitInfo != nil {
        if (try? liveWriterParts(store: store, threadId: threadId)) != nil {
            writerLock = nil
        } else {
            writerLock = try store.acquireWriterLock(threadId)
        }
    } else {
        writerLock = nil
    }
    defer { _ = writerLock }

    var resolvedRollout: ResolvedThreadRollout
    if params.includeArchived {
        guard let resolved = try resolveCurrentIncludingArchived(store: store, threadId: threadId)
        else {
            throw ThreadStoreError.invalidRequest("thread not found: \(threadId)")
        }
        resolvedRollout = resolved
    } else {
        guard let resolved = try resolveCurrent(store: store, threadId: threadId) else {
            throw ThreadStoreError.invalidRequest("thread not found: \(threadId)")
        }
        resolvedRollout = resolved
    }

    if let memoryMode = patch.memoryMode {
        try updateRolloutMetadata(
            store: store,
            threadId: threadId,
            path: resolvedRollout.path
        ) { meta in
            meta.meta.memoryMode = memoryModeAsStr(memoryMode)
        }
        refreshResolvedRolloutPath(&resolvedRollout)
    }

    var resolvedGitInfo: (String?, String?, SanitizedGitUrl?)?
    if let gitInfo = patch.gitInfo {
        let existingMeta: SessionMetaLine
        do {
            existingMeta = try readSessionMetaLine(path: resolvedRollout.path)
        } catch {
            throw ThreadStoreError.internal(
                "failed to update rollout metadata: \(error)")
        }
        if existingMeta.meta.id != threadId {
            throw ThreadStoreError.internal(
                "rollout session metadata id mismatch: expected \(threadId), found \(existingMeta.meta.id)"
            )
        }
        let resolved = resolveGitInfoPatch(existing: existingMeta.git, gitInfo: gitInfo)
        resolvedGitInfo = resolved
        try updateRolloutMetadata(
            store: store,
            threadId: threadId,
            path: resolvedRollout.path
        ) { meta in
            meta.git = GitInfo(
                commitHash: resolved.0.map(GitSha.init),
                branch: resolved.1,
                repositoryUrl: resolved.2
            )
        }
        refreshResolvedRolloutPath(&resolvedRollout)
    }

    var thread: StoredThread
    do {
        thread = try readUpdatedLocalThread(
            store: store,
            threadId: threadId,
            includeArchived: params.includeArchived
        )
    } catch {
        thread = try readLocalThreadByRolloutPath(
            store: store,
            rolloutPath: resolvedRollout.path,
            includeArchived: params.includeArchived,
            includeHistory: false
        )
        overlaySessionIndexName(store: store, thread: &thread)
    }
    if let resolved = resolvedGitInfo {
        thread.gitInfo = gitInfoFromParts(
            sha: resolved.0,
            branch: resolved.1,
            originUrl: resolved.2
        )
    }
    if pendingPatch != nil {
        removePendingThreadMetadata(store: store, threadId: threadId)
    }
    return thread
}

func removePendingThreadMetadata(store: LocalThreadStore, threadId: ThreadId) {
    store.pendingThreadMetadata.remove(threadId: threadId)
}

func refreshResolvedRolloutPath(_ resolved: inout ResolvedThreadRollout) {
    if let path = existingRolloutPath(resolved.path) {
        resolved.path = path
    }
}

func requiresRolloutCompatibilityUpdate(_ patch: ThreadMetadataPatch) -> Bool {
    if patch.memoryMode == nil && patch.gitInfo == nil {
        return false
    }
    return !hasObservedMetadataFacts(patch)
}

func sqliteWriteFailureShouldBlock(_ patch: ThreadMetadataPatch) -> Bool {
    // Before live metadata sync moved above the rollout writer, SQLite sync failures for
    // transcript-derived metadata, thread names, and memory-mode indexing were log-only. Keep that
    // failure isolation so a corrupted optional state DB does not make JSONL transcript durability
    // look broken. Explicit git-only updates still require SQLite because partial git patches need
    // the existing SQLite value to preserve unspecified fields. Project and Daybreak updates
    // require SQLite because those preferences only exist in the state database.
    patch.projectId != nil
        || patch.daybreakEnabled != nil
        || (patch.gitInfo != nil && !hasObservedMetadataFacts(patch))
}

func sqliteWriteErrorIsBestEffort(_ err: ThreadStoreError) -> Bool {
    if case .internal = err { return true }
    return false
}

func hasObservedMetadataFacts(_ patch: ThreadMetadataPatch) -> Bool {
    patch.rolloutPath != nil
        || patch.preview != nil
        || patch.title != nil
        || patch.modelProvider != nil
        || patch.model != nil
        || patch.reasoningEffort != nil
        || patch.createdAt != nil
        || patch.source != nil
        || patch.originator != nil
        || patch.creatorUserId != nil
        || patch.creatorAccountId != nil
        || patch.threadSource != nil
        || patch.agentNickname != nil
        || patch.agentRole != nil
        || patch.agentPath != nil
        || patch.cwd != nil
        || patch.cliVersion != nil
        || patch.approvalMode != nil
        || patch.permissionProfile != nil
        || patch.tokenUsage != nil
        || patch.firstUserMessage != nil
}

/// Fields that only persist through the unported SQLite upsert / title SQL.
func requiresSqliteMetadataPersist(_ patch: ThreadMetadataPatch) -> Bool {
    hasObservedMetadataFacts(patch)
        || patch.updatedAt != nil
        || patch.advanceRecencyAt != nil
        || patch.daybreakEnabled != nil
        || patch.projectId != nil
}

func resolveGitInfoPatch(
    existing: GitInfo?,
    gitInfo: GitInfoPatch
) -> (String?, String?, SanitizedGitUrl?) {
    let existingSha = existing?.commitHash?.value
    let existingBranch = existing?.branch
    let existingOriginUrl = existing?.repositoryUrl
    let sha = gitInfo.sha ?? existingSha
    let branch = gitInfo.branch ?? existingBranch
    let originUrl = gitInfo.originUrl ?? existingOriginUrl
    return (sha, branch, originUrl)
}

/// Rewrite the first JSONL `session_meta` line. Upstream appends a new
/// `SessionMeta` through the live recorder under `live_writer_locks`; this
/// port patches the head line so later `readLocalThread` / `readSessionMetaLine`
/// callers see the update without GRDB overlay.
func updateRolloutMetadata(
    store: LocalThreadStore,
    threadId: ThreadId,
    path: String,
    patch: (inout SessionMetaLine) -> Void
) throws {
    _ = store
    let ioError: (any Error) -> ThreadStoreError = { err in
        .internal("failed to update rollout metadata: \(err)")
    }
    let resolvedPath = existingRolloutPath(path) ?? path
    if isCompressedRolloutPath(resolvedPath) {
        throw ThreadStoreError.internal(
            "failed to update rollout metadata: compressed rollout is not supported yet: \(resolvedPath)"
        )
    }
    var metadata: SessionMetaLine
    do {
        metadata = try readSessionMetaLine(path: resolvedPath)
    } catch {
        throw ioError(error)
    }
    if metadata.meta.id != threadId {
        throw ThreadStoreError.internal(
            "rollout session metadata id mismatch: expected \(threadId), found \(metadata.meta.id)"
        )
    }
    patch(&metadata)

    let text: String
    do {
        text = try String(contentsOfFile: resolvedPath, encoding: .utf8)
    } catch {
        throw ioError(error)
    }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var sessionIndex: Int?
    for (index, raw) in lines.enumerated() {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8)),
              case .object(var fields) = value,
              fields["type"]?.stringValue == "session_meta"
        else {
            continue
        }
        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(metadata)
        } catch {
            throw ioError(error)
        }
        do {
            fields["payload"] = try JSONDecoder().decode(JSONValue.self, from: payloadData)
        } catch {
            throw ioError(error)
        }
        lines[index] = JSONValue.object(fields).encodedString()
        sessionIndex = index
        break
    }
    guard sessionIndex != nil else {
        throw ThreadStoreError.internal(
            "failed to update rollout metadata: missing session metadata")
    }
    do {
        try lines.joined(separator: "\n").write(
            toFile: resolvedPath,
            atomically: true,
            encoding: .utf8
        )
    } catch {
        throw ioError(error)
    }
}

func memoryModeAsStr(_ mode: ThreadMemoryMode) -> String {
    switch mode {
    case .enabled: return "enabled"
    case .disabled: return "disabled"
    }
}

func readUpdatedLocalThread(
    store: LocalThreadStore,
    threadId: ThreadId,
    includeArchived: Bool
) throws -> StoredThread {
    var thread = try readLocalThread(
        store: store,
        params: ReadThreadParams(
            threadId: threadId,
            includeArchived: includeArchived,
            includeHistory: false
        )
    )
    overlaySessionIndexName(store: store, thread: &thread)
    return thread
}

func overlaySessionIndexName(store: LocalThreadStore, thread: inout StoredThread) {
    guard thread.historyMode == .legacy,
          let name = try? findThreadNameById(
            codexHome: store.config.codexHome,
            threadId: thread.threadId
          ),
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return
    }
    setThreadName(&thread, name: name)
}
