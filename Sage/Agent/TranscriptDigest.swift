//
//  TranscriptDigest.swift
//  Sage
//
//  Compact transcript for Plan persist / Review. Not a full tool dump.
//

import Foundation

nonisolated enum TranscriptDigest {
    static func make(from events: [AgentEvent], limit: Int = 16) -> String {
        let relevant = events.filter { event in
            event.kind == .userInput || event.kind == .assistantResponse || event.kind == .toolResult
        }
        let slice = relevant.suffix(limit)
        return slice.map { event in
            switch event.kind {
            case .userInput:
                return "User: \(clip(event.modelFacingContent(includeImagePixels: false)))"

            case .assistantResponse:
                let tools = (event.toolCalls ?? []).map(\.name).joined(separator: ", ")
                if tools.isEmpty {
                    return "Assistant: \(clip(event.content))"
                }
                let prose = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return prose.isEmpty
                    ? "Assistant tools: \(tools)"
                    : "Assistant: \(clip(prose)) [tools: \(tools)]"

            case .toolResult:
                let prefix = event.content.hasPrefix("ERROR:") ? "Tool error" : "Tool result"
                return "\(prefix): \(clip(event.content))"

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
