//
//  rollout_lineage.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_lineage.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Walks `SessionMeta.history_base` over JSONL files via FileManager /
//  `readSessionMetaLine` / `findRolloutPathByRolloutId`. Live-writer locks
//  for `PlainForReference` are omitted. First-segment resolution uses
//  `thread_rollout_resolver`. `materialize_rollout_for_reference` maps to
//  `materializeRolloutForAppend`.
//

import CodexProtocol
import CodexRollout
import Foundation

/// One immutable rollout range contributing to a paginated thread's history.
struct RolloutLineageSegment: Equatable {
    var rolloutId: ThreadId
    var rolloutPath: String
    var startOrdinal: UInt64
    var end: HistoryPosition?

    func endOrdinal() -> UInt64? {
        end.map(\.endOrdinalExclusive)
    }
}

/// Ordered rollout ranges contributing to one forked history.
///
/// This is the only local abstraction that follows SessionMeta.history_base pointers. Readers
/// consume its bounded rollout segments without resolving or mutating fork pointers themselves.
struct RolloutLineage: Equatable {
    var segments: [RolloutLineageSegment]

    func segmentIndexForOrdinal(_ ordinal: UInt64) -> Int? {
        segments.firstIndex { segment in
            ordinal >= segment.startOrdinal
                && (segment.endOrdinal().map { ordinal < $0 } ?? true)
        }
    }

    func truncateAt(_ end: HistoryPosition) throws -> RolloutLineage {
        guard let segmentIndex = segments.firstIndex(where: { $0.rolloutId == end.threadId })
        else {
            throw ThreadStoreError.internal("fork position is outside the source lineage")
        }
        var copy = self
        copy.segments = Array(copy.segments.prefix(segmentIndex + 1))
        guard !copy.segments.isEmpty else {
            throw ThreadStoreError.internal("rollout lineage has no segments")
        }
        try validateCutoffBounds(
            requestedThreadId: end.threadId,
            rolloutPath: copy.segments[copy.segments.count - 1].rolloutPath,
            end: end
        )
        copy.segments[copy.segments.count - 1].end = end
        return copy
    }
}

private enum LineageRepresentation {
    case existing
    case plainForReference
}

extension LocalThreadStore {
    func resolveRolloutLineage(_ requestedThreadId: ThreadId) throws -> RolloutLineage {
        try resolveRolloutLineageWithRepresentation(
            requestedThreadId,
            representation: .existing
        )
    }

    func resolveRolloutLineageForReference(_ requestedThreadId: ThreadId) throws -> RolloutLineage {
        try resolveRolloutLineageWithRepresentation(
            requestedThreadId,
            representation: .plainForReference
        )
    }

    private func resolveRolloutLineageWithRepresentation(
        _ requestedThreadId: ThreadId,
        representation: LineageRepresentation
    ) throws -> RolloutLineage {
        var segments: [RolloutLineageSegment] = []
        var seen = Set<ThreadId>()
        var nextRolloutId: ThreadId?
        var end: HistoryPosition?

        while true {
            let (rolloutId, rawPath): (ThreadId, String)
            if let nextRolloutId {
                guard let path = try resolveRolloutPathById(store: self, rolloutId: nextRolloutId)
                else {
                    throw malformedLineage(nextRolloutId, detail: "missing source rollout")
                }
                rolloutId = nextRolloutId
                rawPath = path
            } else {
                guard let resolved = try resolveCurrentIncludingArchived(
                    store: self,
                    threadId: requestedThreadId
                ) else {
                    throw malformedLineage(requestedThreadId, detail: "missing source rollout")
                }
                rolloutId = resolved.rolloutId
                rawPath = resolved.path
            }
            if !seen.insert(rolloutId).inserted {
                throw malformedLineage(requestedThreadId, detail: "cycle detected")
            }

            let rolloutPath: String
            switch representation {
            case .existing:
                rolloutPath = rawPath
            case .plainForReference:
                rolloutPath = try canonicalizeManagedRolloutPath(store: self, rolloutPath: rawPath)
            }

            let meta: SessionMetaLine
            do {
                meta = try readSessionMetaLine(path: rolloutPath)
            } catch {
                throw ThreadStoreError.internal(
                    "failed to read lineage metadata \(rolloutPath): \(error)")
            }
            if nextRolloutId == nil && meta.meta.id != requestedThreadId {
                throw malformedLineage(
                    requestedThreadId,
                    detail: "source rollout belongs to another thread")
            }
            if meta.meta.historyMode != .paginated {
                throw malformedLineage(
                    requestedThreadId,
                    detail: "source rollout is not paginated")
            }

            let resolvedPath: String
            switch representation {
            case .existing:
                resolvedPath = rolloutPath
            case .plainForReference where nextRolloutId == nil && meta.meta.historyBase == nil:
                do {
                    resolvedPath = try materializeRolloutForAppend(rolloutPath)
                } catch {
                    throw ThreadStoreError.internal(
                        "failed to materialize referenced rollout \(rolloutPath): \(error)")
                }
            case .plainForReference:
                resolvedPath = rolloutPath
            }

            if let end {
                try validateCutoffBounds(
                    requestedThreadId: requestedThreadId,
                    rolloutPath: resolvedPath,
                    end: end
                )
            }
            let startOrdinal: UInt64
            if let base = meta.meta.historyBase {
                guard let next = base.endOrdinalExclusive.checkedAdd(1) else {
                    throw malformedLineage(requestedThreadId, detail: "source ordinal overflow")
                }
                startOrdinal = next
            } else {
                startOrdinal = 1
            }
            segments.append(RolloutLineageSegment(
                rolloutId: rolloutId,
                rolloutPath: resolvedPath,
                startOrdinal: startOrdinal,
                end: end
            ))

            guard let base = meta.meta.historyBase else { break }
            nextRolloutId = base.threadId
            end = base
        }

        segments.reverse()
        return RolloutLineage(segments: segments)
    }
}

private func resolveRolloutPathById(
    store: LocalThreadStore,
    rolloutId: ThreadId
) throws -> String? {
    do {
        return try findRolloutPathByRolloutId(
            codexHome: store.config.codexHome,
            rolloutId: rolloutId
        )
    } catch {
        throw ThreadStoreError.internal("failed to locate rollout \(rolloutId): \(error)")
    }
}

private func canonicalizeManagedRolloutPath(
    store: LocalThreadStore,
    rolloutPath: String
) throws -> String {
    let outsideCodexHome = ThreadStoreError.invalidRequest(
        "rollout path `\(rolloutPath)` must be in Codex home directory")
    guard let canonicalRollout = canonicalizeExistingPath(rolloutPath) else {
        throw outsideCodexHome
    }
    let sessionRoot = (store.config.codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR)
    let archivedRoot = (store.config.codexHome as NSString)
        .appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR)
    let isManaged = [sessionRoot, archivedRoot].contains { root in
        guard let canonicalRoot = canonicalizeExistingPath(root) else { return false }
        return pathIsInside(canonicalRollout, root: canonicalRoot)
    }
    if !isManaged { throw outsideCodexHome }
    return canonicalRollout
}

private func validateCutoffBounds(
    requestedThreadId: ThreadId,
    rolloutPath: String,
    end: HistoryPosition
) throws {
    if end.endOrdinalExclusive == 0 {
        throw malformedLineage(
            requestedThreadId,
            detail: "cutoff cannot include source session metadata")
    }
    let containsPrefix: Bool
    do {
        containsPrefix = try rolloutContainsPrefix(
            path: rolloutPath,
            endByteOffset: end.endByteOffset
        )
    } catch {
        throw ThreadStoreError.internal(
            "failed to read lineage metadata \(rolloutPath): \(error)")
    }
    if !containsPrefix {
        throw malformedLineage(
            requestedThreadId,
            detail: "cutoff byte offset is past the source rollout")
    }
}

private func malformedLineage(_ threadId: ThreadId, detail: String) -> ThreadStoreError {
    .invalidRequest("invalid paginated history lineage for \(threadId): \(detail)")
}

private func canonicalizeExistingPath(_ path: String) -> String? {
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
        return url.resolvingSymlinksInPath().path
    }
    return nil
}

private func pathIsInside(_ path: String, root: String) -> Bool {
    let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
    return path == normalizedRoot || path.hasPrefix(normalizedRoot + "/")
}

private extension UInt64 {
    func checkedAdd(_ other: UInt64) -> UInt64? {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? nil : result
    }
}
