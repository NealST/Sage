//
//  WorkingMemoryParser.swift
//  Sage
//
//  Turns a compact-model reply into TaskWorkingMemory.
//

import Foundation

/// Parses structured JSON / labeled sections, then falls back to plain prose.
nonisolated enum WorkingMemoryParser {
    private struct Payload: Decodable {
        var overview: String?
        var architecture: String?
        var touchedFiles: String?
        var troubleshooting: String?
        var progress: String?
        var focus: String?
        var recentActions: String?
        var nextSteps: String?
        var narrative: String?
    }

    /// Builds a snapshot from the compressor reply. Returns `nil` when nothing usable remains.
    static func parse(
        _ raw: String,
        foldedFromEventID: UUID,
        foldedThroughEventID: UUID,
        sourceModel: String?
    ) -> TaskWorkingMemory? {
        let summary = taggedSlice(raw, tag: "summary") ?? raw
        if let payload = decodePayload(summary) ?? decodePayload(raw) {
            let memory = TaskWorkingMemory.makeStructured(
                foldedFromEventID: foldedFromEventID,
                foldedThroughEventID: foldedThroughEventID,
                sourceModel: sourceModel,
                overview: payload.overview,
                architecture: payload.architecture,
                touchedFiles: payload.touchedFiles,
                troubleshooting: payload.troubleshooting,
                progress: payload.progress,
                focus: payload.focus,
                recentActions: payload.recentActions,
                nextSteps: payload.nextSteps,
                narrative: payload.narrative
            )
            if memory.hasContent { return memory }
        }

        if let labeled = parseLabeled(
            summary,
            foldedFromEventID: foldedFromEventID,
            foldedThroughEventID: foldedThroughEventID,
            sourceModel: sourceModel
        ), labeled.hasContent {
            return labeled
        }

        let narrative = strippingTags(summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !narrative.isEmpty else { return nil }
        return .makeSimple(
            foldedFromEventID: foldedFromEventID,
            foldedThroughEventID: foldedThroughEventID,
            narrative: narrative,
            sourceModel: sourceModel
        )
    }

    static func taggedSlice(_ text: String, tag: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = text.range(of: open, options: .caseInsensitive),
              let end = text.range(of: close, options: .caseInsensitive, range: start.upperBound..<text.endIndex),
              start.upperBound < end.lowerBound
        else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private static func parseLabeled(
        _ text: String,
        foldedFromEventID: UUID,
        foldedThroughEventID: UUID,
        sourceModel: String?
    ) -> TaskWorkingMemory? {
        var buckets: [String: String] = [:]
        var current: String?
        var buffer: [String] = []

        func flush() {
            guard let current else { return }
            let value = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { buckets[current] = value }
            buffer = []
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let colon = line.firstIndex(of: ":") {
                let heading = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                if let key = canonicalKey(heading) {
                    flush()
                    current = key
                    let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    buffer = rest.isEmpty ? [] : [rest]
                    continue
                }
            }
            if current != nil {
                buffer.append(line)
            }
        }
        flush()
        guard !buckets.isEmpty else { return nil }

        return TaskWorkingMemory.makeStructured(
            foldedFromEventID: foldedFromEventID,
            foldedThroughEventID: foldedThroughEventID,
            sourceModel: sourceModel,
            overview: buckets["overview"],
            architecture: buckets["architecture"],
            touchedFiles: buckets["touchedFiles"],
            troubleshooting: buckets["troubleshooting"],
            progress: buckets["progress"],
            focus: buckets["focus"],
            recentActions: buckets["recentActions"],
            nextSteps: buckets["nextSteps"],
            narrative: buckets["narrative"]
        )
    }

    private static func canonicalKey(_ heading: String) -> String? {
        switch heading.lowercased() {
        case "overview", "session overview", "goal": return "overview"
        case "architecture", "technical base": return "architecture"
        case "files", "touched files", "codebase": return "touchedFiles"
        case "troubleshooting", "errors", "problem solving": return "troubleshooting"
        case "progress", "progress tracking": return "progress"
        case "focus", "current focus": return "focus"
        case "recent actions", "behavior", "actions": return "recentActions"
        case "next steps", "plan", "todos": return "nextSteps"
        case "notes", "narrative": return "narrative"
        default: return nil
        }
    }

    private static func strippingTags(_ text: String) -> String {
        var result = text
        if let analysis = taggedSlice(text, tag: "analysis") {
            result = result.replacingOccurrences(of: "<analysis>\(analysis)</analysis>", with: "")
        }
        return result
    }

    private static func decodePayload(_ text: String) -> Payload? {
        guard let jsonString = ModelJSONSlice.objectString(in: text),
              let data = jsonString.data(using: .utf8)
        else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Payload.self, from: data)
    }
}
