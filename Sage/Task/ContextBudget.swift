//
//  ContextBudget.swift
//  Sage
//

import Foundation

/// Caps history sent to cloud models. Prefer recent, paired turns over raw truncation.
enum ContextBudget {
    static let maxEvents = 28
    static let maxCharacters = 24_000

    static func select(from events: [AgentEvent]) -> [AgentEvent] {
        let sanitized = sanitize(events)
        guard !sanitized.isEmpty else { return [] }

        // Protected events (e.g., skill instructions) are always included.
        let protectedEvents = sanitized.filter(\.protected)
        let prunableEvents = sanitized.filter { !$0.protected }

        var selected: [AgentEvent] = []
        var characters = protectedEvents.reduce(0) { $0 + characterCost(of: $1) }
        var index = prunableEvents.count - 1

        while index >= 0 {
            if selected.count + protectedEvents.count >= maxEvents { break }

            let event = prunableEvents[index]
            // Keep assistant tool_calls + following tool results as an atomic block.
            if event.kind == .toolResult {
                var blockStart = index
                while blockStart > 0, prunableEvents[blockStart - 1].kind == .toolResult {
                    blockStart -= 1
                }
                if blockStart > 0,
                   prunableEvents[blockStart - 1].kind == .assistantResponse,
                   let calls = prunableEvents[blockStart - 1].toolCalls,
                   !calls.isEmpty {
                    blockStart -= 1
                }
                let block = Array(prunableEvents[blockStart...index])
                let cost = block.reduce(0) { $0 + characterCost(of: $1) }
                if !selected.isEmpty,
                   selected.count + protectedEvents.count + block.count > maxEvents
                    || characters + cost > maxCharacters {
                    break
                }
                selected.insert(contentsOf: block, at: 0)
                characters += cost
                index = blockStart - 1
                continue
            }

            if event.kind == .assistantResponse,
               let calls = event.toolCalls,
               !calls.isEmpty {
                // Orphan proposal — should already be stripped, skip defensively.
                index -= 1
                continue
            }

            let cost = characterCost(of: event)
            if !selected.isEmpty, characters + cost > maxCharacters {
                break
            }
            selected.insert(event, at: 0)
            characters += cost
            index -= 1
        }

        // Merge protected events back in chronological order.
        return mergeByOrder(protected: protectedEvents, pruned: selected, original: sanitized)
    }

    /// Merges protected and selected events maintaining their original order.
    private static func mergeByOrder(
        protected: [AgentEvent],
        pruned: [AgentEvent],
        original: [AgentEvent]
    ) -> [AgentEvent] {
        let includedIDs = Set(protected.map(\.id)).union(pruned.map(\.id))
        return original.filter { includedIDs.contains($0.id) }
    }

    /// Drops fully unexecuted proposals, truncates partially executed ones,
    /// and removes orphan tool results.
    private static func sanitize(_ events: [AgentEvent]) -> [AgentEvent] {
        let completedCallIDs = Set(
            events.compactMap { event -> String? in
                guard event.kind == .toolResult else { return nil }
                return event.toolCallID
            }
        )

        var kept: [AgentEvent] = []
        for event in events {
            if event.kind == .systemInstruction { continue }

            if event.kind == .assistantResponse,
               let calls = event.toolCalls,
               !calls.isEmpty {
                let completed = calls.filter { completedCallIDs.contains($0.id) }
                guard !completed.isEmpty else { continue }
                var copy = event
                copy.toolCalls = completed
                kept.append(copy)
                continue
            }

            if event.kind == .toolResult {
                guard let callID = event.toolCallID,
                      completedCallIDs.contains(callID)
                else { continue }
                kept.append(event)
                continue
            }

            kept.append(event)
        }

        let keptCallIDs = Set(
            kept.compactMap(\.toolCalls).flatMap { $0 }.map(\.id)
        )
        return kept.filter { event in
            guard event.kind == .toolResult else { return true }
            guard let callID = event.toolCallID else { return false }
            return keptCallIDs.contains(callID)
        }
    }

    private static func characterCost(of event: AgentEvent) -> Int {
        let body = event.kind == .toolResult
            ? WriteFileResultCodec.modelFacing(event.content)
            : event.content
        var cost = max(body.count, 1)
        if let calls = event.toolCalls {
            cost += calls.reduce(0) { $0 + $1.argumentsJSON.count + $1.name.count }
        }
        return cost
    }
}
