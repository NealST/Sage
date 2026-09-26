//
//  rollout_reference_index.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/rollout_reference_index.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Directory walk is FileManager. Compressed siblings hidden by a plain
//  `.jsonl` are skipped via `RolloutFile.fromPath`.
//

import CodexProtocol
import Foundation

/// Direct history-base edges discovered from local rollout metadata.
public struct RolloutReferenceIndex: Sendable {
    private struct IndexedRollout: Sendable {
        var threadId: ThreadId
        var path: String
        var historyBase: HistoryPosition?
    }

    private var rolloutsById: [RolloutId: IndexedRollout]
    private var referenceCountsByRollout: [RolloutId: Int]

    public init() {
        rolloutsById = [:]
        referenceCountsByRollout = [:]
    }

    public static func scan(codexHome: String) throws -> RolloutReferenceIndex {
        try scanPaths([
            (codexHome as NSString).appendingPathComponent(ARCHIVED_SESSIONS_SUBDIR),
            (codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR),
        ], threadIds: nil)
    }

    public static func scanUnarchived(codexHome: String) throws -> RolloutReferenceIndex {
        try scanPaths([
            (codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR),
        ], threadIds: nil)
    }

    public static func scanUnarchivedThreads(
        codexHome: String,
        threadIds: [ThreadId]
    ) throws -> RolloutReferenceIndex {
        try scanPaths([
            (codexHome as NSString).appendingPathComponent(SESSIONS_SUBDIR),
        ], threadIds: Set(threadIds))
    }

    private static func scanPaths(
        _ roots: [String],
        threadIds: Set<ThreadId>?
    ) throws -> RolloutReferenceIndex {
        var rolloutsById: [RolloutId: IndexedRollout] = [:]
        var stack = roots
        while let directory = stack.popLast() {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for name in names {
                let path = (directory as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                if isDir.boolValue {
                    stack.append(path)
                    continue
                }
                guard let rolloutFile = RolloutFile.fromPath(path),
                      let fileName = RolloutFileName.parse(rolloutFile.plainFileName)
                else { continue }
                if let threadIds, !threadIds.contains(fileName.threadId) { continue }
                guard let meta = try? readSessionMetaLine(path: rolloutFile.path) else { continue }
                if rolloutsById[fileName.rolloutId] == nil {
                    rolloutsById[fileName.rolloutId] = IndexedRollout(
                        threadId: meta.meta.id,
                        path: rolloutFile.path,
                        historyBase: meta.meta.historyBase
                    )
                }
            }
        }
        var referenceCounts: [RolloutId: Int] = [:]
        for (rolloutId, rollout) in rolloutsById {
            guard let historyBase = rollout.historyBase, historyBase.threadId != rolloutId else {
                continue
            }
            referenceCounts[historyBase.threadId, default: 0] += 1
        }
        var index = RolloutReferenceIndex()
        index.rolloutsById = rolloutsById
        index.referenceCountsByRollout = referenceCounts
        return index
    }

    public func referenceCount(_ rolloutId: RolloutId) -> Int {
        referenceCountsByRollout[rolloutId] ?? 0
    }

    public func historyBase(_ rolloutId: RolloutId) -> HistoryPosition? {
        rolloutsById[rolloutId]?.historyBase
    }

    public func rolloutsForThread(_ threadId: ThreadId) -> [(RolloutId, String)] {
        rolloutsById.compactMap { id, rollout in
            rollout.threadId == threadId ? (id, rollout.path) : nil
        }
    }
}
