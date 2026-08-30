//
//  TranscriptDigest.swift
//  Sage
//
//  Compact transcript for Plan persist / Review. Not a full tool dump.
//

import Foundation

nonisolated enum TranscriptDigest {
    static func makeCurrentTurn(from events: [AgentEvent]) -> String {
        guard let start = events.lastIndex(where: { $0.kind == .userInput }) else {
            return make(from: events, limit: 32, clip: 2_000)
        }
        return make(from: Array(events[start...]), limit: 32, clip: 2_000)
    }

    static func make(from events: [AgentEvent], limit: Int = 16, clip: Int = 400) -> String {
        let relevant = events.filter { event in
            event.kind == .userInput || event.kind == .assistantResponse || event.kind == .toolResult
        }
        let slice = relevant.suffix(limit)
        return slice.map { event in
            switch event.kind {
            case .userInput:
                return "User: \(self.clip(event.modelFacingContent(includeImagePixels: false), max: clip))"

            case .assistantResponse:
                let tools = (event.toolCalls ?? []).map(\.name).joined(separator: ", ")
                if tools.isEmpty {
                    return "Assistant: \(self.clip(event.content, max: clip))"
                }
                let prose = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return prose.isEmpty
                    ? "Assistant tools: \(tools)"
                    : "Assistant: \(self.clip(prose, max: clip)) [tools: \(tools)]"

            case .toolResult:
                let prefix = event.content.hasPrefix("ERROR:") ? "Tool error" : "Tool result"
                return "\(prefix): \(self.clip(event.content, max: clip))"

            case .systemInstruction:
                return ""
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func clip(_ text: String, max: Int = 400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max)) + "…"
    }
}
