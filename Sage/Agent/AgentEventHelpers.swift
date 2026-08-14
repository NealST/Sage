//
//  AgentEventHelpers.swift
//  Sage
//

import Foundation

nonisolated enum AgentEventHelpers {
    /// Assistant tool-proposal events that never received a matching tool result.
    static func unexecutedToolProposalIDs(in events: [AgentEvent]) -> [UUID] {
        let completed = Set(
            events.compactMap { event -> String? in
                guard event.kind == .toolResult else { return nil }
                return event.toolCallID
            }
        )
        return events.compactMap { event in
            guard event.kind == .assistantResponse,
                  let calls = event.toolCalls,
                  !calls.isEmpty,
                  !calls.contains(where: { completed.contains($0.id) })
            else { return nil }
            return event.id
        }
    }

    static func hasSuccessfulToolResult(for toolCallID: String, in events: [AgentEvent]) -> Bool {
        events.contains {
            $0.kind == .toolResult
                && $0.toolCallID == toolCallID
                && !$0.content.hasPrefix("ERROR:")
        }
    }
}

nonisolated enum ContextHint {
    static func forResumedTask(topic: String?, summary: String?) -> String {
        if let topic = topic?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty {
            return "Using context from \u{201C}\(topic)\u{201D}"
        }
        if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            let clipped = summary.count > 48
                ? String(summary.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                : summary
            return "Using context from \u{201C}\(clipped)\u{201D}"
        }
        return "Using context from a related task"
    }

    static func forTask(_ task: TaskRecord) -> String {
        forResumedTask(topic: task.topic, summary: task.summary)
    }
}
