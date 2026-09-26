//
//  model_context.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/model_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Loads latest model context from JSONL via `readSessionMetaLine`,
//  `loadHistoryItems`, `ModelContextScan`, and `ReverseJsonlScanner`.
//  Path resolution uses `thread_rollout_resolver`. `tokio::task::spawn_blocking`
//  is omitted (scans run in-process).
//

import CodexHistory
import CodexProtocol
import CodexRollout
import Foundation

/// Loads rollout items needed to reconstruct the latest model-visible context.
///
/// Paginated JSONL rollouts use a reverse scan. It stops at the newest `CompactedItem` with both
/// replacement history and a window number, and returns that compaction plus its newer suffix. If
/// the newest compaction lacks either field, the scan continues to the beginning of the rollout.
///
/// Compressed segments are decoded before applying their original JSONL offsets. Legacy rollouts
/// keep the existing full-history path.
func loadLatestLocalModelContext(
    store: LocalThreadStore,
    params: LoadThreadHistoryParams
) throws -> StoredModelContext {
    let resolved: ResolvedThreadRollout?
    if params.includeArchived {
        resolved = try resolveCurrentIncludingArchived(store: store, threadId: params.threadId)
    } else {
        resolved = try resolveCurrent(store: store, threadId: params.threadId)
    }
    guard let path = resolved?.path else {
        throw ThreadStoreError.invalidRequest(
            "no rollout found for thread id \(params.threadId)")
    }
    let sessionMeta: SessionMetaLine
    do {
        sessionMeta = try readSessionMetaLine(path: path)
    } catch {
        throw ThreadStoreError.internal(
            "failed to read session metadata \(path): \(error)")
    }
    if sessionMeta.meta.id != params.threadId {
        throw ThreadStoreError.invalidRequest(
            "rollout at \(path) belongs to thread \(sessionMeta.meta.id), not \(params.threadId)")
    }

    let items: [RolloutItem]
    if sessionMeta.meta.historyMode == .paginated {
        let lineage = try store.resolveRolloutLineage(params.threadId)
        items = try scanModelContextFromLineage(lineage, sessionMeta: sessionMeta)
    } else {
        items = try loadHistoryItems(path: path)
    }
    return StoredModelContext(threadId: params.threadId, items: items)
}

/// Loads startup context from a fork's frozen inherited prefix.
func loadForFork(
    lineage: RolloutLineage,
    historyBase: HistoryPosition?
) throws -> [RolloutItem] {
    guard let sourcePath = lineage.segments.last?.rolloutPath else {
        throw ThreadStoreError.internal("fork lineage has no source segment")
    }
    var sessionMeta: SessionMetaLine
    do {
        sessionMeta = try readSessionMetaLine(path: sourcePath)
    } catch {
        throw ThreadStoreError.internal(
            "failed to read session metadata \(sourcePath): \(error)")
    }
    if sessionMeta.meta.multiAgentVersion == nil {
        sessionMeta.meta.multiAgentVersion = try scanForkRuntimeVersion(lineage)
    }
    guard let historyBase else {
        return [.sessionMeta(sessionMeta)]
    }
    let truncated = try lineage.truncateAt(historyBase)
    return try scanModelContextFromLineage(truncated, sessionMeta: sessionMeta)
}

func scanModelContextFromLineage(
    _ lineage: RolloutLineage,
    sessionMeta: SessionMetaLine
) throws -> [RolloutItem] {
    do {
        return try scanModelContextFromLineageBlocking(lineage, sessionMeta: sessionMeta)
    } catch {
        throw ThreadStoreError.internal(
            "failed to scan paginated model context lineage: \(error)")
    }
}

private func scanModelContextFromLineageBlocking(
    _ lineage: RolloutLineage,
    sessionMeta: SessionMetaLine
) throws -> [RolloutItem] {
    var scan = ModelContextScan()
    segmentLoop: for segment in lineage.segments.reversed() {
        let handle = try openRolloutSeekableReader(path: segment.rolloutPath)
        defer { try? handle.close() }
        let scanner: ReverseJsonlScanner
        if let end = segment.end {
            scanner = try ReverseJsonlScanner(handle, endByteOffset: end.endByteOffset)
        } else {
            scanner = try ReverseJsonlScanner(handle)
        }
        while let outcome = try scanner.scanNextRolloutLine() {
            guard case .parsed(let line) = outcome else { continue }
            // Each rollout segment contributes only its local delta. Its session metadata is
            // replaced with the requested thread's canonical SessionMeta after replay.
            if case .sessionMeta = line.item { break }
            switch scan.push(line.item) {
            case .continue:
                break
            case .complete:
                break segmentLoop
            }
        }
    }
    var items = scan.finish()
    items.insert(.sessionMeta(sessionMeta), at: 0)
    return items
}

private func scanForkRuntimeVersion(_ lineage: RolloutLineage) throws -> MultiAgentVersion? {
    do {
        for segment in lineage.segments.reversed() {
            let handle = try openRolloutSeekableReader(path: segment.rolloutPath)
            defer { try? handle.close() }
            let scanner: ReverseJsonlScanner
            if let end = segment.end {
                scanner = try ReverseJsonlScanner(handle, endByteOffset: end.endByteOffset)
            } else {
                scanner = try ReverseJsonlScanner(handle)
            }
            while let outcome = try scanner.scanNextRolloutLine() {
                guard case .parsed(let line) = outcome else { continue }
                if let version = resumeMultiAgentVersion(line.item) {
                    return version
                }
                // Ancestor metadata does not describe the immediate source's runtime.
                if case .sessionMeta = line.item { break }
            }
        }
        return nil
    } catch {
        throw ThreadStoreError.internal("failed to read fork runtime version: \(error)")
    }
}

/// Returns the runtime version stored in a turn context or compaction resume metadata.
func resumeMultiAgentVersion(_ item: RolloutItem) -> MultiAgentVersion? {
    switch item {
    case .turnContext(let context):
        return context.multiAgentVersion
    case .compacted(let compacted):
        guard let raw = compacted.resumeMetadata?.objectValue?["multi_agent_version"]?.stringValue
        else { return nil }
        return MultiAgentVersion(rawValue: raw)
    default:
        return nil
    }
}
