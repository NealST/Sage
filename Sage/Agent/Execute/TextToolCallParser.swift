//
//  TextToolCallParser.swift
//  Sage
//
//  Recovers tool calls that the model wrote as text instead of API tool_calls.
//

import Foundation

/// Some models (or gateways) dump a DSML / XML tool script into `content`
/// instead of emitting structured `tool_calls`. Sage would otherwise store
/// that dump as the assistant reply and never run anything.
nonisolated enum TextToolCallParser {
    struct Parsed: Sendable, Equatable {
        var prose: String?
        var calls: [ToolCallProposal]
    }

    /// Text that is safe to stream / show — markup from the first tool script onward is dropped.
    static func visibleText(in buffer: String) -> String {
        guard let start = markupStart(in: buffer) else { return buffer }
        return String(buffer[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func recover(
        from text: String,
        existing: [ToolCallProposal]
    ) -> (content: String?, calls: [ToolCallProposal]) {
        if !existing.isEmpty {
            return (visibleText(in: text).nilIfEmpty, existing)
        }
        if let parsed = parse(text) {
            return (parsed.prose, parsed.calls)
        }
        if markupStart(in: text) != nil {
            return (visibleText(in: text).nilIfEmpty, [])
        }
        return (text.nilIfEmpty, [])
    }

    static func parse(_ text: String) -> Parsed? {
        let xml = unwrapDSML(text)
        guard looksLikeToolMarkup(xml) else { return nil }

        let calls = invokeBlocks(in: xml).compactMap(proposal(from:))
        guard !calls.isEmpty else { return nil }

        let prose = visibleText(in: text).nilIfEmpty
        return Parsed(prose: prose, calls: calls)
    }

    // MARK: - Markup

    static func markupStart(in buffer: String) -> String.Index? {
        let markers = ["<｜", "<|", "<tool_calls", "<invoke "]
        var earliest: String.Index?
        for marker in markers {
            guard let range = buffer.range(of: marker) else { continue }
            if earliest == nil || range.lowerBound < earliest! {
                earliest = range.lowerBound
            }
        }
        return earliest
    }

    private static func looksLikeToolMarkup(_ text: String) -> Bool {
        text.contains("<invoke") || text.contains("<tool_calls")
    }

    /// `<｜｜DSML｜｜invoke …>` / `</｜｜DSML｜｜invoke>` → `<invoke …>` / `</invoke>`
    private static func unwrapDSML(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(/?)[|｜]{1,8}DSML[|｜]{1,8}([A-Za-z0-9_]+)([^>]*)>"#
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "<$1$2$3>"
        )
    }

    private static func invokeBlocks(in xml: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<invoke\s+name="([^"]+)"\s*>(.*?)</invoke>"#,
            options: .dotMatchesLineSeparators
        ) else {
            return []
        }
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: xml),
                  let bodyRange = Range(match.range(at: 2), in: xml)
            else { return nil }
            return "\(xml[nameRange])\u{1e}\(xml[bodyRange])"
        }
    }

    private static func proposal(from packed: String) -> ToolCallProposal? {
        let parts = packed.split(separator: "\u{1e}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let rawName = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { return nil }

        let name = SkillToolPolicy.canonicalizeToolName(rawName)
        let arguments = parametersJSON(in: String(parts[1]))
        return ToolCallProposal(
            id: "text_call_\(UUID().uuidString.prefix(8))",
            name: name,
            argumentsJSON: arguments
        )
    }

    private static func parametersJSON(in body: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<parameter\s+name="([^"]+)"[^>]*>(.*?)</parameter>"#,
            options: .dotMatchesLineSeparators
        ) else {
            return "{}"
        }
        let range = NSRange(body.startIndex..., in: body)
        var object: [String: String] = [:]
        for match in regex.matches(in: body, range: range) {
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: body),
                  let valueRange = Range(match.range(at: 2), in: body)
            else { continue }
            let key = String(body[nameRange])
            let value = String(body[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            object[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }
}
