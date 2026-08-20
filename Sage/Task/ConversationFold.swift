//
//  ConversationFold.swift
//  Sage
//
//  Chooses which transcript prefix a working-memory snapshot should cover.
//

import Foundation

/// Near-end keep + far-end fold. Incremental compact starts after an existing snapshot.
nonisolated enum ConversationFold {
    /// User turns left verbatim after a fold (the current discussion).
    static let keptRecentUserTurns = 2
    /// Minimum events in a new fold span. Avoids compacting a single short line.
    static let minimumSpanEvents = 2

    /// Events that should be folded, or `nil` when there isn't enough history.
    static func span(
        in events: [AgentEvent],
        existing: TaskWorkingMemory?
    ) -> (fromEventID: UUID, throughEventID: UUID)? {
        let timeline = events.filter { $0.kind != .systemInstruction }
        guard !timeline.isEmpty else { return nil }

        let userIndices = timeline.indices.filter { timeline[$0].kind == .userInput }
        guard userIndices.count > keptRecentUserTurns else { return nil }

        let keepFrom = userIndices[userIndices.count - keptRecentUserTurns]
        guard keepFrom > 0 else { return nil }
        let throughIndex = keepFrom - 1

        let startIndex: Int
        if let existing {
            guard let end = timeline.firstIndex(where: { $0.id == existing.foldedThroughEventID }) else {
                return nil
            }
            startIndex = end + 1
        } else {
            startIndex = 0
        }

        guard startIndex <= throughIndex else { return nil }
        let span = timeline[startIndex...throughIndex]
        guard span.count >= minimumSpanEvents, let first = span.first, let last = span.last else {
            return nil
        }
        return (first.id, last.id)
    }

    /// Events from `from` through `through`, in order.
    static func slice(
        _ events: [AgentEvent],
        from fromID: UUID,
        through throughID: UUID
    ) -> [AgentEvent] {
        guard let fromIndex = events.firstIndex(where: { $0.id == fromID }),
              let throughIndex = events.firstIndex(where: { $0.id == throughID }),
              fromIndex <= throughIndex
        else {
            return []
        }
        return Array(events[fromIndex...throughIndex])
    }
}
