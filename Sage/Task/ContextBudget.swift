//
//  ContextBudget.swift
//  Sage
//

import Foundation

/// Caps history sent to cloud models. Prefer recent, paired turns over raw truncation.
enum ContextBudget {
    static let maxEvents = 28
    static let maxCharacters = 24_000
    /// Soft ceiling for one protected skill payload (auto-load / slash / `load_skill`).
    /// Aligns with Agent Skills progressive-disclosure guidance: keep SKILL.md bodies
    /// around ≤5,000 tokens (≈10–15k characters). Use the upper bound so in-spec skills
    /// are not truncated; oversize bodies stub and point at `load_skill_resource`.
    static let maxSkillContentCharacters = 15_000
    /// Aggregate ceiling for all protected events so multiple skill loads cannot starve dialogue.
    /// Leaves at least ~8k of the 24k transcript budget for non-protected turns.
    static let maxProtectedCharacters = 16_000

    /// Truncates oversized skill bodies and points the model at progressive resource loading.
    static func capSkillContent(_ content: String, skillName: String) -> String {
        guard content.utf8.count > maxSkillContentCharacters else { return content }
        let head = utf8Prefix(content, maxBytes: maxSkillContentCharacters)
        return """
        \(head)

        … [skill '\(skillName)' truncated at \(maxSkillContentCharacters) characters (~5k-token progressive-disclosure limit)]
        Use `load_skill_resource` for remaining reference material under this skill.
        """
    }

    static func select(from events: [AgentEvent]) -> [AgentEvent] {
        let sanitized = sanitize(events)
        guard !sanitized.isEmpty else { return [] }

        // Protected events stay in context, but are per-skill capped and then fit to an
        // aggregate protected budget (newest skill payloads preferred).
        let protectedEvents = fitProtectedBudget(
            sanitized.filter(\.protected).map(capProtectedEvent(_:))
        )
        let prunableEvents = sanitized.filter { !$0.protected }

        // Collect newest-first, then reverse — avoids O(n²) `insert(at: 0)`.
        var selectedReversed: [AgentEvent] = []
        var characters = protectedEvents.reduce(0) { $0 + characterCost(of: $1) }
        var index = prunableEvents.count - 1

        while index >= 0 {
            if selectedReversed.count + protectedEvents.count >= maxEvents { break }

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
                if !selectedReversed.isEmpty,
                   selectedReversed.count + protectedEvents.count + block.count > maxEvents
                    || characters + cost > maxCharacters {
                    break
                }
                selectedReversed.append(contentsOf: block.reversed())
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
            if !selectedReversed.isEmpty, characters + cost > maxCharacters {
                break
            }
            selectedReversed.append(event)
            characters += cost
            index -= 1
        }

        let selected = Array(selectedReversed.reversed())

        // Merge protected events back in chronological order.
        return mergeByOrder(protected: protectedEvents, pruned: selected, original: sanitized)
    }

    /// Caps protected skill payloads that were stored before injection-time budgeting.
    private static func capProtectedEvent(_ event: AgentEvent) -> AgentEvent {
        guard event.content.utf8.count > maxSkillContentCharacters else { return event }
        var copy = event
        let name = inferredSkillName(from: event.content) ?? "skill"
        copy.content = capSkillContent(event.content, skillName: name)
        return copy
    }

    /// Prefer newest protected payloads; stub older skill bodies when the aggregate budget is exceeded.
    private static func fitProtectedBudget(_ events: [AgentEvent]) -> [AgentEvent] {
        var result = events
        var cost = result.reduce(0) { $0 + characterCost(of: $1) }
        guard cost > maxProtectedCharacters else { return result }

        for index in result.indices {
            guard cost > maxProtectedCharacters else { break }
            let event = result[index]
            let before = characterCost(of: event)
            guard before > 400, looksLikeSkillPayload(event) else { continue }

            var stub = event
            let name = inferredSkillName(from: event.content) ?? "skill"
            stub.content = """
            [Earlier skill '\(name)' omitted from context to stay within the protected budget. \
            Call `load_skill` again if you still need its instructions.]
            """
            result[index] = stub
            cost += characterCost(of: stub) - before
        }
        return result
    }

    private static func looksLikeSkillPayload(_ event: AgentEvent) -> Bool {
        let content = event.content
        return content.contains("<skill_content")
            || content.contains("[Activated skill:")
            || content.contains("skill_resources")
    }

    private static func inferredSkillName(from content: String) -> String? {
        // <skill_content name="…"> or "[Activated skill: …]"
        if let range = content.range(of: #"name="([^"]+)""#, options: .regularExpression) {
            let matched = String(content[range])
            if let open = matched.firstIndex(of: "\""),
               let close = matched.lastIndex(of: "\""),
               open < close {
                let start = matched.index(after: open)
                return String(matched[start..<close])
            }
        }
        if let range = content.range(of: #"\[Activated skill: ([^\]]+)\]"#, options: .regularExpression) {
            let matched = String(content[range])
            if let colon = matched.firstIndex(of: ":") {
                let name = matched[matched.index(after: colon)...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ]"))
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    /// Merges protected and selected events maintaining their original order.
    /// Protected copies (possibly capped) override the originals by id.
    private static func mergeByOrder(
        protected: [AgentEvent],
        pruned: [AgentEvent],
        original: [AgentEvent]
    ) -> [AgentEvent] {
        var byID: [UUID: AgentEvent] = [:]
        for event in pruned {
            byID[event.id] = event
        }
        for event in protected {
            byID[event.id] = event
        }
        return original.compactMap { byID[$0.id] }
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
        // UTF-8 byte length is stable and closer to tokenizers than grapheme count.
        var cost = max(body.utf8.count, 1)
        if let calls = event.toolCalls {
            cost += calls.reduce(0) {
                $0 + $1.argumentsJSON.utf8.count + $1.name.utf8.count
            }
        }
        return cost
    }

    /// Prefix truncated on a Character boundary so the result stays valid UTF-8.
    private static func utf8Prefix(_ string: String, maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else { return string }
        var byteCount = 0
        var end = string.startIndex
        for index in string.indices {
            let charBytes = string[index].utf8.count
            if byteCount + charBytes > maxBytes { break }
            byteCount += charBytes
            end = string.index(after: index)
        }
        return String(string[..<end])
    }
}
