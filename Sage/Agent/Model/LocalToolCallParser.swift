//
//  LocalToolCallParser.swift
//  Sage
//
//  Parses tool calls that local (MLX) models emit as text markup — the
//  Qwen3 / Hermes "" JSON blocks and the older Qwen2 ""
//  form — into structured proposals, plus a streaming filter that keeps
//  the markup out of the visible reply.
//

import Foundation

nonisolated enum LocalToolCallParser {
    struct Parsed: Sendable, Equatable {
        var prose: String?
        var calls: [ToolCallProposal]
    }

    /// Marker pairs that wrap tool-call JSON bodies, in precedence order.
    private static let blockPairs: [(open: String, close: String)] = [
        ("", ""),
        ("", ""),
        ("", "")
    ]

    /// Section tokens some templates emit around the blocks.
    private static let sectionTokens = [
        "<｜tool▁calls｜>",
        "<｜tool_calls｜>",
        "<|tool_calls|>",
        "<|tool▁calls|>"
    ]

    private static var allMarkers: [String] {
        blockPairs.flatMap { [$0.open, $0.close] } + sectionTokens
    }

    // MARK: - Whole-text parsing

    /// Text that is safe to show — everything before the first marker.
    static func visibleText(in buffer: String) -> String {
        guard let start = markerStart(in: buffer) else { return buffer }
        return String(buffer[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func markerStart(in buffer: String) -> String.Index? {
        var earliest: String.Index?
        for marker in allMarkers {
            guard let range = buffer.range(of: marker) else { continue }
            if let current = earliest, range.lowerBound >= current { continue }
            earliest = range.lowerBound
        }
        return earliest
    }

    /// Parses a completed generation. Returns nil when the text contains no
    /// recoverable tool call.
    static func parse(_ text: String) -> Parsed? {
        let prose = visibleText(in: text).nilIfEmpty
        var calls: [ToolCallProposal] = []

        for pair in blockPairs {
            let blocks = blocks(between: pair.open, and: pair.close, in: text)
            let parsed = blocks.flatMap(calls(inBlock:))
            if !parsed.isEmpty {
                calls = parsed
                break
            }
        }

        if calls.isEmpty, let tokenRange = earliestSectionToken(in: text) {
            calls = calls(inBlock: String(text[tokenRange.upperBound...]))
        }

        guard !calls.isEmpty else { return nil }
        return Parsed(prose: prose, calls: calls)
    }

    private static func earliestSectionToken(in text: String) -> Range<String.Index>? {
        var earliest: Range<String.Index>?
        for token in sectionTokens {
            guard let range = text.range(of: token) else { continue }
            if let current = earliest, range.lowerBound >= current.lowerBound { continue }
            earliest = range
        }
        return earliest
    }

    private static func blocks(
        between open: String,
        and close: String,
        in text: String
    ) -> [String] {
        var results: [String] = []
        var searchStart = text.startIndex
        while let openRange = text.range(of: open, range: searchStart..<text.endIndex) {
            let contentStart = openRange.upperBound
            guard let closeRange = text.range(of: close, range: contentStart..<text.endIndex) else {
                results.append(String(text[contentStart...]))
                return results
            }
            results.append(String(text[contentStart..<closeRange.lowerBound]))
            searchStart = closeRange.upperBound
        }
        return results
    }

    // MARK: - JSON extraction

    private static func calls(inBlock block: String) -> [ToolCallProposal] {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let whole = call(fromJSON: trimmed.data(using: .utf8) ?? Data()) {
            return [whole]
        }

        return trimmed
            .split(separator: "\n")
            .compactMap { line in
                call(fromJSON: String(line).data(using: .utf8) ?? Data())
            }
    }

    private static func call(fromJSON data: Data) -> ToolCallProposal? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String,
              !name.isEmpty
        else {
            return nil
        }
        return ToolCallProposal(
            id: "local_\(UUID().uuidString.prefix(8))",
            name: SkillToolPolicy.canonicalizeToolName(name),
            argumentsJSON: argumentsJSON(from: object["arguments"] ?? object["parameters"])
        )
    }

    private static func argumentsJSON(from value: Any) -> String {
        if let string = value as? String {
            if let data = string.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return string
            }
            let data = (try? JSONSerialization.data(withJSONObject: string)) ?? Data("{}".utf8)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }
}

// MARK: - Streaming filter

/// Accumulates generation tokens and hands back only the text that is safe
/// to stream to the user, holding back suffixes that could still turn into
/// a marker and suppressing everything from the first complete marker on.
struct LocalToolCallStreamFilter: Sendable {
    private var buffer = ""
    private var emittedOffset = 0
    private var suppressing = false

    /// Feeds one generation delta; returns newly safe-to-show text.
    mutating func push(_ delta: String) -> String? {
        buffer += delta
        guard !suppressing else { return nil }

        if let start = LocalToolCallParser.markerStart(in: buffer) {
            suppressing = true
            let startOffset = buffer.distance(from: buffer.startIndex, to: start)
            guard startOffset > emittedOffset else { return nil }
            let from = buffer.index(buffer.startIndex, offsetBy: emittedOffset)
            let chunk = String(buffer[from..<start])
            emittedOffset = startOffset
            return chunk.isEmpty ? nil : chunk
        }

        let holdback = partialMarkerSuffixLength
        let safeOffset = buffer.count - holdback
        guard safeOffset > emittedOffset else { return nil }
        let from = buffer.index(buffer.startIndex, offsetBy: emittedOffset)
        let to = buffer.index(buffer.startIndex, offsetBy: safeOffset)
        let chunk = String(buffer[from..<to])
        emittedOffset = safeOffset
        return chunk.isEmpty ? nil : chunk
    }

    /// Final result of the generation.
    func finalize() -> LocalToolCallParser.Parsed {
        if let parsed = LocalToolCallParser.parse(buffer) {
            return parsed
        }
        if LocalToolCallParser.markerStart(in: buffer) != nil {
            return .init(prose: LocalToolCallParser.visibleText(in: buffer).nilIfEmpty, calls: [])
        }
        return .init(prose: buffer.isEmpty ? nil : buffer, calls: [])
    }

    /// Longest suffix of the buffer (shorter than any marker) that is still a
    /// plausible marker prefix and must not be streamed yet.
    private var partialMarkerSuffixLength: Int {
        let markers = [
            "<｜tool▁calls｜>",
            "<｜tool_calls｜>",
            "<|tool_calls|>",
            "<|tool▁calls|>",
            "",
            "",
            "",
            ""
        ]
        let maxMarker = markers.map(\.count).max() ?? 0
        for length in stride(from: min(maxMarker - 1, buffer.count), through: 1, by: -1) {
            guard length <= buffer.count else { continue }
            let suffix = buffer.suffix(length)
            if markers.contains(where: { $0.hasPrefix(suffix) }) {
                return length
            }
        }
        return 0
    }
}
