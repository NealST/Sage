//
//  LineDiff.swift
//  Sage
//

import Foundation

/// Line-oriented diff ops (Myers O(ND)).
nonisolated enum LineDiff {
    enum Op: Equatable, Sendable {
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
        for op in diff(before: before, after: after) {
            switch op {
            case .insert: insertions += 1
            case .delete: deletions += 1
            case .equal: break
            }
        }
        return Stats(insertions: insertions, deletions: deletions)
    }

    static func diff(before: String, after: String) -> [Op] {
        diffLines(splitLines(before), splitLines(after))
    }

    /// Collapse long equal runs, keeping `context` lines at each edge.
    static func withCollapsedContext(_ ops: [Op], context: Int = 3) -> [Op] {
        guard context >= 0 else { return ops }
        var result: [Op] = []
        var i = 0
        while i < ops.count {
            guard case .equal = ops[i] else {
                result.append(ops[i])
                i += 1
                continue
            }
            var j = i
            while j < ops.count, case .equal = ops[j] { j += 1 }
            let run = Array(ops[i..<j])
            if run.count <= context * 2 + 1 {
                result.append(contentsOf: run)
            } else {
                result.append(contentsOf: run.prefix(context))
                result.append(.equal("⋯ \(run.count - context * 2) unchanged lines ⋯"))
                result.append(contentsOf: run.suffix(context))
            }
            i = j
        }
        return result
    }

    // MARK: - Myers

    private static func diffLines(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count
        let m = b.count
        if n == 0 { return b.map { .insert($0) } }
        if m == 0 { return a.map { .delete($0) } }

        let maxD = n + m
        let offset = maxD
        var v = Array(repeating: 0, count: 2 * maxD + 1)
        var trace: [[Int]] = []

        for d in 0...maxD {
            for k in stride(from: -d, through: d, by: 2) {
                let idx = k + offset
                var x: Int
                if k == -d || (k != d && v[idx - 1] < v[idx + 1]) {
                    x = v[idx + 1]
                } else {
                    x = v[idx - 1] + 1
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[idx] = x
                if x >= n, y >= m {
                    trace.append(v)
                    return backtrack(a: a, b: b, trace: trace, offset: offset)
                }
            }
            trace.append(v)
        }

        return backtrack(a: a, b: b, trace: trace, offset: offset)
    }

    private static func backtrack(
        a: [String],
        b: [String],
        trace: [[Int]],
        offset: Int
    ) -> [Op] {
        var x = a.count
        var y = b.count
        var ops: [Op] = []

        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let prevK: Int
            if d > 0 {
                if k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset]) {
                    prevK = k + 1
                } else {
                    prevK = k - 1
                }
            } else {
                prevK = 0
            }
            let prevX = d > 0 ? v[prevK + offset] : 0
            let prevY = prevX - prevK

            while x > prevX, y > prevY {
                ops.append(.equal(a[x - 1]))
                x -= 1
                y -= 1
            }

            if d == 0 { break }

            if x == prevX {
                ops.append(.insert(b[y - 1]))
                y -= 1
            } else {
                ops.append(.delete(a[x - 1]))
                x -= 1
            }
        }

        return ops.reversed()
    }

    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
