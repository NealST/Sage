//
//  ContextBudget+Fitting.swift
//  Sage
//

import Foundation

nonisolated extension ContextBudget {
    // MARK: - Fitting

    static func fitUser(_ event: AgentEvent?, tokenBudget: Int) -> AgentEvent? {
        guard var event else { return nil }
        guard tokenBudget > 0 else { return nil }
        let bytes = PromptBudget.utf8ByteCount(of: event)
        let maxBytes = tokenBudget * PromptBudget.bytesPerToken
        guard bytes > maxBytes else { return event }
        event.content = utf8Prefix(event.content, maxBytes: maxBytes)
            + "\n… [user message truncated to fit context budget]"
        return event
    }

    static func truncateUser(_ event: AgentEvent?, tokenBudget: Int) -> AgentEvent? {
        fitUser(event, tokenBudget: max(tokenBudget, 1))
    }

    /// Newest-first fill. Tool-call + result blocks stay atomic; oversized results middle-out.
    static func fitEvents(
        _ events: [AgentEvent],
        tokenBudget: Int,
        forceIncludeNewest: Bool
    ) -> [AgentEvent] {
        guard !events.isEmpty, tokenBudget > 0 else {
            if forceIncludeNewest, let last = events.last {
                return fitEvents([last], tokenBudget: max(tokenBudget, 1), forceIncludeNewest: false)
            }
            return []
        }

        var selectedReversed: [AgentEvent] = []
        var tokens = 0
        var index = events.count - 1

        while index >= 0 {
            let event = events[index]
            if event.kind == .toolResult {
                if !appendToolBlock(
                    events: events,
                    index: &index,
                    tokenBudget: tokenBudget,
                    tokens: &tokens,
                    selectedReversed: &selectedReversed
                ) {
                    break
                }
                continue
            }
            if event.kind == .assistantResponse,
               let calls = event.toolCalls,
               !calls.isEmpty {
                index -= 1
                continue
            }
            if !appendStandaloneEvent(
                event,
                tokenBudget: tokenBudget,
                tokens: &tokens,
                selectedReversed: &selectedReversed,
                forceIncludeNewest: forceIncludeNewest
            ) {
                break
            }
            index -= 1
        }

        return Array(selectedReversed.reversed())
    }

    static func appendToolBlock(
        events: [AgentEvent],
        index: inout Int,
        tokenBudget: Int,
        tokens: inout Int,
        selectedReversed: inout [AgentEvent]
    ) -> Bool {
        var blockStart = index
        while blockStart > 0, events[blockStart - 1].kind == .toolResult {
            blockStart -= 1
        }
        if blockStart > 0,
           events[blockStart - 1].kind == .assistantResponse,
           let calls = events[blockStart - 1].toolCalls,
           !calls.isEmpty {
            blockStart -= 1
        }
        var block = Array(events[blockStart...index])
        let cost = tokenCount(of: block)
        let room = tokenBudget - tokens
        if cost > room {
            if selectedReversed.isEmpty {
                block = shrinkToolBlock(block, tokenBudget: max(room, 1))
                selectedReversed.append(contentsOf: block.reversed())
            }
            return false
        }
        selectedReversed.append(contentsOf: block.reversed())
        tokens += cost
        index = blockStart - 1
        return true
    }

    static func appendStandaloneEvent(
        _ event: AgentEvent,
        tokenBudget: Int,
        tokens: inout Int,
        selectedReversed: inout [AgentEvent],
        forceIncludeNewest: Bool
    ) -> Bool {
        let cost = PromptBudget.estimatedTokenCount(of: event)
        if tokens + cost > tokenBudget, !selectedReversed.isEmpty {
            return false
        }
        if tokens + cost > tokenBudget, selectedReversed.isEmpty, forceIncludeNewest {
            if let copy = fitUser(event, tokenBudget: tokenBudget) {
                selectedReversed.append(copy)
                tokens += PromptBudget.estimatedTokenCount(of: copy)
            }
            return false
        }
        if tokens + cost > tokenBudget {
            return false
        }
        selectedReversed.append(event)
        tokens += cost
        return true
    }

    static func shrinkToolBlock(_ block: [AgentEvent], tokenBudget: Int) -> [AgentEvent] {
        let current = tokenCount(of: block)
        guard current > tokenBudget else { return block }
        let resultCount = max(block.filter { $0.kind == .toolResult }.count, 1)
        let tokensEach = max(tokenBudget / resultCount, 16)
        return block.map { event in
            guard event.kind == .toolResult else { return event }
            return capToolResult(event, maxTokens: tokensEach)
        }
    }

    // MARK: - Tool / skill caps

    static func middleOut(_ string: String, maxUTF8Bytes: Int) -> String {
        let bytes = string.utf8.count
        guard bytes > maxUTF8Bytes, maxUTF8Bytes > 0 else { return string }
        let marker = middleOmitMarker
        let markerBytes = marker.utf8.count
        guard maxUTF8Bytes > markerBytes + 8 else {
            return utf8Prefix(string, maxBytes: maxUTF8Bytes)
        }
        let keep = maxUTF8Bytes - markerBytes
        let headBytes = max((keep * 2) / 5, 1)
        let tailBytes = max(keep - headBytes, 1)
        let head = utf8Prefix(string, maxBytes: headBytes)
        let tail = utf8Suffix(string, maxBytes: tailBytes)
        return head + marker + tail
    }

    static func capToolResult(_ event: AgentEvent, maxTokens: Int) -> AgentEvent {
        guard event.kind == .toolResult else { return event }
        let body = WriteFileResultCodec.modelFacing(event.content)
        let originalTokens = PromptBudget.estimatedTokenCount(in: body)
        guard originalTokens > maxTokens else { return event }
        var copy = event
        copy.content = middleOutByTokens(
            body,
            maxTokens: maxTokens,
            originalTokens: originalTokens
        )
        return copy
    }

    /// Deterministic tool-result summary: preserve evidence at both ends and
    /// account for CJK/emoji using the same estimator as the prompt budget.
    static func middleOutByTokens(
        _ string: String,
        maxTokens: Int,
        originalTokens: Int
    ) -> String {
        let marker = "\n… [tool result compacted from ~\(originalTokens) tokens] …\n"
        let markerCost = PromptBudget.estimatedTokenCount(in: marker)
        guard maxTokens > markerCost + 2 else {
            return utf8Prefix(string, maxBytes: max(maxTokens * 2, 8))
        }

        let characters = Array(string)
        let keep = maxTokens - markerCost
        let headBudget = max((keep * 2) / 5, 1)
        let tailBudget = max(keep - headBudget, 1)

        var head: [Character] = []
        var headCost = 0
        for character in characters {
            let cost = PromptBudget.estimatedTokenCount(in: String(character))
            guard headCost + cost <= headBudget else { break }
            head.append(character)
            headCost += cost
        }

        var tail: [Character] = []
        var tailCost = 0
        for character in characters.reversed() {
            let cost = PromptBudget.estimatedTokenCount(in: String(character))
            guard tailCost + cost <= tailBudget else { break }
            tail.append(character)
            tailCost += cost
        }
        return String(head) + marker + String(tail.reversed())
    }

    static func capProtectedEvent(_ event: AgentEvent) -> AgentEvent {
        guard event.content.utf8.count > maxSkillContentCharacters else { return event }
        var copy = event
        let name = inferredSkillName(from: event.content) ?? "skill"
        copy.content = capSkillContent(event.content, skillName: name)
        return copy
    }

    static func fitProtectedBudget(_ events: [AgentEvent], maxTokens: Int) -> [AgentEvent] {
        var result = events
        var cost = tokenCount(of: result)
        guard cost > maxTokens else { return result }

        for index in result.indices {
            guard cost > maxTokens else { break }
            let event = result[index]
            let before = PromptBudget.estimatedTokenCount(of: event)
            guard before > 40, looksLikeSkillPayload(event) else { continue }

            var stub = event
            let name = inferredSkillName(from: event.content) ?? "skill"
            stub.content = """
            [Earlier skill '\(name)' omitted from context to stay within the protected budget. \
            Call `load_skill` again if you still need its instructions.]
            """
            result[index] = stub
            cost += PromptBudget.estimatedTokenCount(of: stub) - before
        }
        return result
    }

    static func looksLikeSkillPayload(_ event: AgentEvent) -> Bool {
        let content = event.content
        return content.contains("<skill_content")
            || content.contains("[Activated skill:")
            || content.contains("skill_resources")
    }

    static func inferredSkillName(from content: String) -> String? {
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
                let afterColon = matched.index(after: colon)
                let name = matched[afterColon...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ]"))
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    /// Drops fully unexecuted proposals, truncates partially executed ones,
    /// and removes orphan tool results.
    static func sanitize(_ events: [AgentEvent]) -> [AgentEvent] {
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

    static func utf8Prefix(_ string: String, maxBytes: Int) -> String {
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

    static func utf8Suffix(_ string: String, maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else { return string }
        var byteCount = 0
        var start = string.endIndex
        for index in string.indices.reversed() {
            let charBytes = string[index].utf8.count
            if byteCount + charBytes > maxBytes { break }
            byteCount += charBytes
            start = index
        }
        return String(string[start...])
    }
}
