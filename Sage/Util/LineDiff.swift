//
//  LineDiff.swift
//  Sage
//

import Foundation

/// Line-oriented diff ops (Myers O(ND)).
nonisolated enum LineDiff {
    enum Operation: Equatable, Sendable {
        case equal(String)
        case insert(String)
        case delete(String)
    }

    struct Stats: Equatable, Sendable {
        var insertions: Int
        var deletions: Int

        var isIdentity: Bool { insertions == 0 && deletions == 0 }

        var summary: String {
            if isIdentity { return "no changes" }
            return "+\(insertions)/−\(deletions)"
        }
    }

    static func stats(before: String, after: String) -> Stats {
        var insertions = 0
        var deletions = 0
        for operation in diff(before: before, after: after) {
            switch operation {
            case .insert: insertions += 1
            case .delete: deletions += 1
            case .equal: break
            }
        }
        return Stats(insertions: insertions, deletions: deletions)
    }

    static func diff(before: String, after: String) -> [Operation] {
        diffLines(splitLines(before), splitLines(after))
    }

    /// Collapse long equal runs, keeping `context` lines at each edge.
    static func withCollapsedContext(_ operations: [Operation], context: Int = 3) -> [Operation] {
        guard context >= 0 else { return operations }
        var result: [Operation] = []
        var startIndex = 0
        while startIndex < operations.count {
            guard case .equal = operations[startIndex] else {
                result.append(operations[startIndex])
                startIndex += 1
                continue
            }
            var endIndex = startIndex
            while endIndex < operations.count, case .equal = operations[endIndex] {
                endIndex += 1
            }
            let run = Array(operations[startIndex..<endIndex])
            if run.count <= context * 2 + 1 {
                result.append(contentsOf: run)
            } else {
                result.append(contentsOf: run.prefix(context))
                result.append(.equal("⋯ \(run.count - context * 2) unchanged lines ⋯"))
                result.append(contentsOf: run.suffix(context))
            }
            startIndex = endIndex
        }
        return result
    }

    // MARK: - Myers

    private static func diffLines(_ beforeLines: [String], _ afterLines: [String]) -> [Operation] {
        let beforeCount = beforeLines.count
        let afterCount = afterLines.count
        if beforeCount == 0 { return afterLines.map { .insert($0) } }
        if afterCount == 0 { return beforeLines.map { .delete($0) } }

        let maxDistance = beforeCount + afterCount
        let offset = maxDistance
        var frontier = Array(repeating: 0, count: 2 * maxDistance + 1)
        var trace: [[Int]] = []

        for distance in 0...maxDistance {
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                let idx = diagonal + offset
                var beforeIndex: Int
                if diagonal == -distance || (diagonal != distance && frontier[idx - 1] < frontier[idx + 1]) {
                    beforeIndex = frontier[idx + 1]
                } else {
                    beforeIndex = frontier[idx - 1] + 1
                }
                var afterIndex = beforeIndex - diagonal
                while beforeIndex < beforeCount,
                      afterIndex < afterCount,
                      beforeLines[beforeIndex] == afterLines[afterIndex] {
                    beforeIndex += 1
                    afterIndex += 1
                }
                frontier[idx] = beforeIndex
                if beforeIndex >= beforeCount, afterIndex >= afterCount {
                    trace.append(frontier)
                    return backtrack(
                        beforeLines: beforeLines,
                        afterLines: afterLines,
                        trace: trace,
                        offset: offset
                    )
                }
            }
            trace.append(frontier)
        }

        return backtrack(
            beforeLines: beforeLines,
            afterLines: afterLines,
            trace: trace,
            offset: offset
        )
    }

    private static func backtrack(
        beforeLines: [String],
        afterLines: [String],
        trace: [[Int]],
        offset: Int
    ) -> [Operation] {
        var beforeIndex = beforeLines.count
        var afterIndex = afterLines.count
        var operations: [Operation] = []

        for distance in stride(from: trace.count - 1, through: 0, by: -1) {
            let frontier = trace[distance]
            let diagonal = beforeIndex - afterIndex
            let previousDiagonal: Int
            if distance > 0 {
                if diagonal == -distance
                    || (diagonal != distance && frontier[diagonal - 1 + offset] < frontier[diagonal + 1 + offset]) {
                    previousDiagonal = diagonal + 1
                } else {
                    previousDiagonal = diagonal - 1
                }
            } else {
                previousDiagonal = 0
            }
            let previousBeforeIndex = distance > 0 ? frontier[previousDiagonal + offset] : 0
            let previousAfterIndex = previousBeforeIndex - previousDiagonal

            while beforeIndex > previousBeforeIndex, afterIndex > previousAfterIndex {
                operations.append(.equal(beforeLines[beforeIndex - 1]))
                beforeIndex -= 1
                afterIndex -= 1
            }

            if distance == 0 { break }

            if beforeIndex == previousBeforeIndex {
                operations.append(.insert(afterLines[afterIndex - 1]))
                afterIndex -= 1
            } else {
                operations.append(.delete(beforeLines[beforeIndex - 1]))
                beforeIndex -= 1
            }
        }

        return operations.reversed()
    }

    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }
}
