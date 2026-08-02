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

        var selected: [AgentEvent] = []
        var characters = 0
        var index = sanitized.count - 1

        while index >= 0 {
            if selected.count >= maxEvents { break }

            let event = sanitized[index]
            // Keep assistant tool_calls + following tool results as an atomic block.
            if event.kind == .toolResult {
                var blockStart = index
                while blockStart > 0, sanitized[blockStart - 1].kind == .toolResult {
                    blockStart -= 1
                }
                if blockStart > 0,
                   sanitized[blockStart - 1].kind == .assistantResponse,
                   let calls = sanitized[blockStart - 1].toolCalls,
                   !calls.isEmpty {
                    blockStart -= 1
                }
                let block = Array(sanitized[blockStart...index])
                let cost = block.reduce(0) { $0 + characterCost(of: $1) }
                if !selected.isEmpty,
                   selected.count + block.count > maxEvents
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

        return selected
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
        var cost = max(event.content.count, 1)
        if let calls = event.toolCalls {
            cost += calls.reduce(0) { $0 + $1.argumentsJSON.count + $1.name.count }
        }
        return cost
    }
}
