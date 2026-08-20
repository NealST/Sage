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

    /// Tool call IDs that already have a non-ERROR result. Scan once per batch.
    static func successfulToolCallIDs(in events: [AgentEvent]) -> Set<String> {
        Set(events.compactMap { event in
            guard event.kind == .toolResult,
                  let id = event.toolCallID,
                  !event.content.hasPrefix("ERROR:")
            else { return nil }
            return id
        })
    }

    /// Fork at a user message: that input starts a new task; later replies stay off both threads.
    static func forkLastUserInput(
        events: [AgentEvent],
        userEventID: UUID
    ) -> (kept: [AgentEvent], moved: AgentEvent, discarded: [AgentEvent])? {
        guard let index = events.firstIndex(where: {
            $0.id == userEventID && $0.kind == .userInput
        }) else { return nil }
        let userEvent = events[index]
        let kept = Array(events[..<index])
        let discarded = Array(events[(index + 1)...])
        return (kept, userEvent, discarded)
    }
}
