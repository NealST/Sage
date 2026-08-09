//
//  WriteFileResult.swift
//  Sage
//

import Foundation

/// Structured write-file outcome embedded after the model-facing summary line.
/// UI parses this for before/after diffs; API messages strip it to protect context.
nonisolated struct WriteFileDiffPayload: Codable, Equatable, Sendable {
    var path: String
    var created: Bool
    var before: String?
    var after: String
    var insertions: Int
    var deletions: Int
    /// True when before/after were clipped to fit the tool-result size budget.
    var truncated: Bool

    var stats: LineDiff.Stats {
        LineDiff.Stats(insertions: insertions, deletions: deletions)
    }
}

enum WriteFileResultCodec {
    static let beginMarker = "\n<<<sage_write_diff>>>\n"
    static let endMarker = "\n<<<end_sage_write_diff>>>"

    /// Keep embedded payload comfortably under `toolResultMaxChars` (50k).
    private static let maxEmbeddedChars = 40_000
    private static let minSideChars = 2_000

    static func makeResult(
        path: String,
        created: Bool,
        before: String?,
        after: String
    ) -> String {
        let prior = created ? "" : (before ?? "")
        let stats = LineDiff.stats(before: prior, after: after)

        var payload = WriteFileDiffPayload(
            path: path,
            created: created,
            before: created ? nil : before,
            after: after,
            insertions: stats.insertions,
            deletions: stats.deletions,
            truncated: false
        )
        payload = fitToBudget(payload)

        let verb = created ? "Created" : "Overwrote"
        let bytes = after.utf8.count
        let change = created ? "new file, \(stats.insertions) lines" : stats.summary
        let summary = "[OK] \(verb) \(path) (\(change), \(bytes) bytes)"
        return embed(summary: summary, payload: payload)
    }

    static func embed(summary: String, payload: WriteFileDiffPayload) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return summary
        }
        return summary + beginMarker + json + endMarker
    }

    /// Model-facing / budget-facing content (summary only).
    static func modelFacing(_ content: String) -> String {
        split(content).summary
    }

    static func split(_ content: String) -> (summary: String, payload: WriteFileDiffPayload?) {
        guard let begin = content.range(of: beginMarker),
              let end = content.range(of: endMarker, range: begin.upperBound..<content.endIndex)
        else {
            return (content, nil)
        }
        let summary = String(content[..<begin.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let json = String(content[begin.upperBound..<end.lowerBound])
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(WriteFileDiffPayload.self, from: data)
        else {
            return (summary.isEmpty ? content : summary, nil)
        }
        return (summary.isEmpty ? content : summary, payload)
    }

    static func payload(in content: String) -> WriteFileDiffPayload? {
        split(content).payload
    }

    // MARK: - Budget

    private static func fitToBudget(_ payload: WriteFileDiffPayload) -> WriteFileDiffPayload {
        var payload = payload
        guard encodedLength(payload) <= maxEmbeddedChars else {
            return truncateSides(payload)
        }
        return payload
    }

    private static func truncateSides(_ payload: WriteFileDiffPayload) -> WriteFileDiffPayload {
        var payload = payload
        payload.truncated = true
        // Binary-search a shared per-side budget.
        var low = minSideChars
        var high = max(payload.after.count, payload.before?.count ?? 0)
        var best = payload
        while low <= high {
            let mid = (low + high) / 2
            var candidate = payload
            candidate.after = clip(payload.after, maxChars: mid)
            if let before = payload.before {
                candidate.before = clip(before, maxChars: mid)
            }
            if encodedLength(candidate) <= maxEmbeddedChars {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        // Absolute floor — drop before if still too large.
        if encodedLength(best) > maxEmbeddedChars {
            best.before = nil
            best.after = clip(payload.after, maxChars: minSideChars)
            best.truncated = true
        }
        return best
    }

    private static func clip(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }
        let head = maxChars * 2 / 3
        let tail = maxChars - head
        return String(text.prefix(head))
            + "\n… (truncated for diff preview) …\n"
            + String(text.suffix(tail))
    }

    private static func encodedLength(_ payload: WriteFileDiffPayload) -> Int {
        guard let data = try? JSONEncoder().encode(payload) else { return Int.max }
        return beginMarker.count + data.count + endMarker.count
    }
}
