//
//  WorkspaceChangeSet.swift
//  Sage
//
//  Net workspace mutations from the first execute write until Review / finalize.
//

import Foundation

nonisolated enum WorkspaceChangeKind: String, Codable, Sendable {
    case added
    case modified
    case removed
    case moved
    case copied
    case directory
}

nonisolated struct WorkspaceFileChange: Codable, Equatable, Sendable, Identifiable {
    var path: String
    var kind: WorkspaceChangeKind
    var before: String?
    var after: String?
    var insertions: Int
    var deletions: Int
    var truncated: Bool
    var previousPath: String?

    var id: String {
        if let previousPath {
            return "\(previousPath)>\(path)"
        }
        return path
    }

    var hasLineDiff: Bool {
        switch kind {
        case .added, .modified, .removed:
            return before != nil || after != nil

        case .moved, .copied, .directory:
            return false
        }
    }

    var stats: LineDiff.Stats {
        LineDiff.Stats(insertions: insertions, deletions: deletions)
    }
}

nonisolated struct WorkspaceChangeSet: Codable, Equatable, Sendable {
    var files: [WorkspaceFileChange]
    var opaqueMutationCount: Int

    static let empty = Self(files: [], opaqueMutationCount: 0)

    var isEmpty: Bool {
        files.isEmpty && opaqueMutationCount == 0
    }

    var totalStats: LineDiff.Stats {
        files.reduce(into: LineDiff.Stats(insertions: 0, deletions: 0)) { totals, file in
            totals.insertions += file.insertions
            totals.deletions += file.deletions
        }
    }
}

/// Folds discrete file-tool results into a baseline→current book for one work cycle.
nonisolated struct WorkspaceChangeBook: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var path: String
        var previousPath: String?
        var baseline: String?
        var current: String?
        var createdThisTurn: Bool
        var kind: WorkspaceChangeKind
        var metadataOnly: Bool
    }

    private(set) var entries: [String: Entry] = [:]
    private(set) var opaqueMutationCount = 0

    mutating func applyWrite(path: String, before: String?, after: String, created: Bool) {
        var entry = entries[path] ?? Entry(
            path: path,
            previousPath: nil,
            baseline: created ? nil : before,
            current: before,
            createdThisTurn: created,
            kind: created ? .added : .modified,
            metadataOnly: false
        )
        if entries[path] == nil, !created, before == nil {
            entry.baseline = nil
        }
        entry.current = after
        entry.metadataOnly = false
        entry.kind = entry.createdThisTurn ? .added : .modified
        entries[path] = entry
        dropIfNetZero(path)
    }

    mutating func applyDelete(path: String) {
        guard var entry = entries[path] else {
            entries[path] = Entry(
                path: path,
                previousPath: nil,
                baseline: nil,
                current: nil,
                createdThisTurn: false,
                kind: .removed,
                metadataOnly: true
            )
            return
        }
        entry.current = nil
        entry.kind = .removed
        entries[path] = entry
        dropIfNetZero(path)
    }

    mutating func applyMove(from source: String, to destination: String) {
        let existing = entries.removeValue(forKey: source)
        var entry = existing ?? Entry(
            path: destination,
            previousPath: source,
            baseline: nil,
            current: nil,
            createdThisTurn: false,
            kind: .moved,
            metadataOnly: true
        )
        entry.previousPath = existing?.previousPath ?? source
        entry.path = destination
        if entry.kind != .added && entry.kind != .removed {
            entry.kind = .moved
        }
        entries[destination] = entry
        dropIfNetZero(destination)
    }

    mutating func applyCopied(path: String) {
        entries[path] = Entry(
            path: path,
            previousPath: nil,
            baseline: nil,
            current: nil,
            createdThisTurn: true,
            kind: .copied,
            metadataOnly: true
        )
    }

    mutating func applyDirectory(path: String) {
        entries[path] = Entry(
            path: path,
            previousPath: nil,
            baseline: nil,
            current: nil,
            createdThisTurn: true,
            kind: .directory,
            metadataOnly: true
        )
    }

    mutating func markOpaque() {
        opaqueMutationCount += 1
    }

    mutating func reset() {
        entries = [:]
        opaqueMutationCount = 0
    }
}

extension WorkspaceChangeBook {
    func snapshot() -> WorkspaceChangeSet {
        let files = entries.values
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
            .compactMap(Self.fileChange(from:))
        return WorkspaceChangeSet(files: files, opaqueMutationCount: opaqueMutationCount)
    }

    private mutating func dropIfNetZero(_ path: String) {
        guard let entry = entries[path] else { return }
        if entry.createdThisTurn, entry.current == nil {
            entries[path] = nil
            return
        }
        if !entry.metadataOnly, entry.current == entry.baseline, entry.previousPath == nil {
            entries[path] = nil
        }
    }

    private static func fileChange(from entry: Entry) -> WorkspaceFileChange? {
        if entry.createdThisTurn, entry.current == nil { return nil }
        if !entry.metadataOnly, entry.current == entry.baseline, entry.previousPath == nil {
            return nil
        }
        let prior = entry.createdThisTurn ? "" : (entry.baseline ?? "")
        let next = entry.current ?? ""
        let stats = entry.metadataOnly
            ? LineDiff.Stats(insertions: 0, deletions: 0)
            : LineDiff.stats(before: prior, after: next)
        return WorkspaceFileChange(
            path: entry.path,
            kind: entry.kind,
            before: entry.metadataOnly ? nil : entry.baseline,
            after: entry.metadataOnly ? nil : entry.current,
            insertions: stats.insertions,
            deletions: stats.deletions,
            truncated: false,
            previousPath: entry.previousPath
        )
    }
}
