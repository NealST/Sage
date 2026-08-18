//
//  ContextBudget.swift
//  Sage
//
//  Priority + flexGrow prompt assembly. Lossless prune before summarization.
//

import Foundation

/// Inputs for one model-facing prompt. Empty strings are skipped.
nonisolated struct PromptLayout: Sendable {
    var budget: PromptBudget
    var baseInstructions: String = ""
    var projectAppendix: String = ""
    var workPlanAppendix: String = ""
    var workingMemory: TaskWorkingMemory? = nil
    var reviewFeedback: String = ""
    var skillsCatalog: String = ""
    var relatedSnippets: [RelatedTaskContextSnippet] = []
    var events: [AgentEvent] = []
}

/// System text + transcript after lossless region scheduling.
nonisolated struct PromptAssembly: Sendable {
    var events: [AgentEvent]
    /// True when pinned regions still overflow `usableTokens` after shrinking droppable slices.
    var didExceedBudget: Bool
    /// Assembled prompt tokens ÷ usable budget, capped at 1.
    var occupancy: Double
    var assembledTokens: Int
    var usableTokens: Int
}

/// Caps history sent to cloud models. Prefer recent, paired turns over raw truncation.
nonisolated enum ContextBudget {
    /// Soft ceiling for one protected skill payload (slash / `load_skill`).
    /// Aligns with Agent Skills progressive-disclosure guidance: keep SKILL.md bodies
    /// around ≤5,000 tokens (≈10–15k characters). Use the upper bound so in-spec skills
    /// are not truncated; oversize bodies stub and point at `load_skill_resource`.
    static let maxSkillContentCharacters = 15_000

    private static let middleOmitMarker = "\n… [middle omitted to fit context budget]\n"
    private static let skillsCatalogStub = """

    ## Available Skills
    Skill catalog omitted to stay within the context budget. Use `load_skill` if you know the name.
    """

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

    /// Transcript-only selection. Uses `PromptBudget.default` when the caller has no model.
    static func select(
        from events: [AgentEvent],
        budget: PromptBudget = .default
    ) -> [AgentEvent] {
        assemble(PromptLayout(budget: budget, events: events)).events
            .filter { $0.kind != .systemInstruction }
    }

    /// Schedules system slices and transcript events into `layout.budget.usableTokens`.
    static func assemble(_ layout: PromptLayout) -> PromptAssembly {
        let budget = layout.budget
        let sanitized = sanitize(layout.events).map {
            capToolResult($0, maxUTF8Bytes: budget.maxToolResultUTF8Bytes)
        }

        let memory = layout.workingMemory?.validated(against: layout.events)
        let activeMemory = (memory?.hasContent == true) ? memory : nil
        let memoryAppendix = activeMemory?.promptAppendix ?? ""

        let lastUser = sanitized.last { $0.kind == .userInput && !$0.protected }
        let lastUserID = lastUser?.id
        let lastUserIndex = lastUser.flatMap { user in
            sanitized.firstIndex(where: { $0.id == user.id })
        }

        var folded = Set(activeMemory?.foldedEventIDs(in: layout.events) ?? [])
        if let lastUserID {
            folded.remove(lastUserID)
        }

        var currentUser: AgentEvent?
        var latestTurn: [AgentEvent] = []
        var history: [AgentEvent] = []
        var protectedSkills: [AgentEvent] = []
        var prefixOrder: [AgentEvent] = []

        for (index, event) in sanitized.enumerated() {
            if folded.contains(event.id) { continue }
            if let lastUserIndex, index > lastUserIndex {
                latestTurn.append(event)
                continue
            }
            if event.id == lastUserID {
                currentUser = event
                continue
            }
            if event.protected {
                let capped = capProtectedEvent(event)
                protectedSkills.append(capped)
                prefixOrder.append(capped)
                continue
            }
            history.append(event)
            prefixOrder.append(event)
        }

        var relatedMode = RelatedRenderMode.full
        var skillsCatalog = layout.skillsCatalog
        var projectAppendix = layout.projectAppendix

        let nonFlexBase = [
            layout.baseInstructions,
            layout.workPlanAppendix,
            memoryAppendix,
            layout.reviewFeedback,
        ]
        func nonFlexTokens() -> Int {
            let related = renderRelated(layout.relatedSnippets, mode: relatedMode)
            return tokenCount(in: nonFlexBase + [projectAppendix, skillsCatalog, related])
        }

        // Drop lowest-priority system slices until pin + a little headroom fit,
        // or until nothing droppable remains.
        if nonFlexTokens() + pinTokens(user: currentUser, latest: latestTurn)
            > budget.usableTokens {
            relatedMode = .titles
        }
        if nonFlexTokens() + pinTokens(user: currentUser, latest: latestTurn)
            > budget.usableTokens {
            relatedMode = .omitted
        }
        if nonFlexTokens() + pinTokens(user: currentUser, latest: latestTurn)
            > budget.usableTokens,
           !skillsCatalog.isEmpty {
            skillsCatalog = skillsCatalogStub
        }
        if nonFlexTokens() + pinTokens(user: currentUser, latest: latestTurn)
            > budget.usableTokens,
           projectAppendix.utf8.count > 1_200 {
            let cap = max(budget.usableTokens / 8, 200) * PromptBudget.bytesPerToken
            projectAppendix = middleOut(projectAppendix, maxUTF8Bytes: cap)
        }

        let nonFlex = nonFlexTokens()
        var remaining = budget.usableTokens - nonFlex
        let pinOverflow = remaining < pinTokens(user: currentUser, latest: latestTurn)

        // Flex shares: current user 2, latest turn 2, history 1, older skills 1.
        let growUser = currentUser == nil ? 0 : 2
        let growLatest = latestTurn.isEmpty ? 0 : 2
        let growHistory = history.isEmpty ? 0 : 1
        let growSkills = protectedSkills.isEmpty ? 0 : 1
        let totalGrow = growUser + growLatest + growHistory + growSkills

        if remaining <= 0 || totalGrow == 0 {
            let fittedUser = remaining > 0
                ? fitUser(currentUser, tokenBudget: remaining)
                : (growUser == 0 ? currentUser : truncateUser(currentUser, tokenBudget: max(remaining, 1)))
            let usedUser = fittedUser.map { PromptBudget.estimatedTokenCount(of: $0) } ?? 0
            remaining -= usedUser
            let fittedLatest = fitEvents(
                latestTurn,
                tokenBudget: max(remaining, 0),
                forceIncludeNewest: remaining > 0
            )
            let usedLatest = tokenCount(of: fittedLatest)
            remaining -= usedLatest
            let system = renderSystem(
                layout: layout,
                projectAppendix: projectAppendix,
                workingMemoryAppendix: memoryAppendix,
                skillsCatalog: skillsCatalog,
                relatedMode: relatedMode
            )
            return finish(
                events: stitch(
                    system: system,
                    user: fittedUser,
                    latest: fittedLatest,
                    protected: [],
                    history: [],
                    prefixOrder: []
                ),
                didExceedBudget: pinOverflow || remaining < 0,
                usableTokens: budget.usableTokens
            )
        }

        func share(_ grow: Int) -> Int {
            guard totalGrow > 0, grow > 0 else { return 0 }
            return remaining * grow / totalGrow
        }

        let userShare = growUser == 0 ? 0 : max(share(growUser), 1)
        let latestShare = growLatest == 0 ? 0 : max(share(growLatest), 1)
        let skillsShare = share(growSkills)
        let (fittedUser, unusedUser) = takeFlex(
            share: userShare,
            fit: { fitUser(currentUser, tokenBudget: $0) },
            cost: { $0.map { PromptBudget.estimatedTokenCount(of: $0) } ?? 0 }
        )
        let (fittedLatest, unusedLatest) = takeFlex(
            share: latestShare,
            fit: { fitEvents(latestTurn, tokenBudget: $0, forceIncludeNewest: true) },
            cost: { tokenCount(of: $0) }
        )
        let (fittedSkills, unusedSkills) = takeFlex(
            share: skillsShare,
            fit: { tokens in
                tokens > 0 ? fitProtectedBudget(protectedSkills, maxTokens: tokens) : []
            },
            cost: { tokenCount(of: $0) }
        )
        let historyBudget = max(
            remaining - userShare - latestShare - skillsShare,
            0
        ) + unusedUser + unusedLatest + unusedSkills
        let fittedHistory = fitEvents(
            history,
            tokenBudget: historyBudget,
            forceIncludeNewest: false
        )

        let system = renderSystem(
            layout: layout,
            projectAppendix: projectAppendix,
            workingMemoryAppendix: memoryAppendix,
            skillsCatalog: skillsCatalog,
            relatedMode: relatedMode
        )
        return finish(
            events: stitch(
                system: system,
                user: fittedUser,
                latest: fittedLatest,
                protected: fittedSkills,
                history: fittedHistory,
                prefixOrder: prefixOrder
            ),
            didExceedBudget: pinOverflow,
            usableTokens: budget.usableTokens
        )
    }

    private static func finish(
        events: [AgentEvent],
        didExceedBudget: Bool,
        usableTokens: Int
    ) -> PromptAssembly {
        let assembled = tokenCount(of: events)
        let occupancy: Double
        if usableTokens <= 0 {
            occupancy = 1
        } else {
            occupancy = min(1, Double(assembled) / Double(usableTokens))
        }
        return PromptAssembly(
            events: events,
            didExceedBudget: didExceedBudget,
            occupancy: occupancy,
            assembledTokens: assembled,
            usableTokens: usableTokens
        )
    }

    // MARK: - Flex helpers

    private static func takeFlex<T>(
        share: Int,
        fit: (Int) -> T,
        cost: (T) -> Int
    ) -> (T, unused: Int) {
        let fitted = fit(max(share, 0))
        let used = cost(fitted)
        return (fitted, max(share - used, 0))
    }

    private static func pinTokens(user: AgentEvent?, latest: [AgentEvent]) -> Int {
        (user.map { PromptBudget.estimatedTokenCount(of: $0) } ?? 0) + tokenCount(of: latest)
    }

    private static func tokenCount(in texts: [String]) -> Int {
        texts.reduce(0) { $0 + PromptBudget.estimatedTokenCount(in: $1) }
    }

    private static func tokenCount(of events: [AgentEvent]) -> Int {
        events.reduce(0) { $0 + PromptBudget.estimatedTokenCount(of: $1) }
    }

    // MARK: - System rendering

    private enum RelatedRenderMode {
        case full
        case titles
        case omitted
    }

    private static func renderSystem(
        layout: PromptLayout,
        projectAppendix: String,
        workingMemoryAppendix: String,
        skillsCatalog: String,
        relatedMode: RelatedRenderMode
    ) -> String {
        [
            layout.baseInstructions,
            projectAppendix,
            layout.workPlanAppendix,
            workingMemoryAppendix,
            layout.reviewFeedback,
            skillsCatalog,
            renderRelated(layout.relatedSnippets, mode: relatedMode),
        ]
        .filter { !$0.isEmpty }
        .joined()
    }

    private static func renderRelated(
        _ snippets: [RelatedTaskContextSnippet],
        mode: RelatedRenderMode
    ) -> String {
        guard mode != .omitted, !snippets.isEmpty else { return "" }
        var lines = ["", "## Related prior work", "Use only if relevant to the current request:"]
        for related in snippets {
            let topic = related.topic?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let summary = related.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let title = topic ?? summary ?? "Prior task"
            lines.append("- \(title)")
            if let abstract = related.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
               !abstract.isEmpty {
                lines.append("  Intent: \(abstract)")
            }
            guard mode == .full else { continue }
            for turn in related.recentDialogue {
                let clipped = String(
                    turn.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220)
                )
                guard !clipped.isEmpty else { continue }
                switch turn.kind {
                case .user:
                    lines.append("  User: \(clipped)")
                case .assistant:
                    lines.append("  Assistant: \(clipped)")
                }
            }
        }
        return lines.count > 3 ? lines.joined(separator: "\n") : ""
    }

    private static func stitch(
        system: String,
        user: AgentEvent?,
        latest: [AgentEvent],
        protected: [AgentEvent],
        history: [AgentEvent],
        prefixOrder: [AgentEvent]
    ) -> [AgentEvent] {
        let mergedPrefix = mergeByOriginalOrder(
            protected: protected,
            pruned: history,
            originals: prefixOrder
        )
        var result: [AgentEvent] = []
        if !system.isEmpty {
            result.append(AgentEvent(kind: .systemInstruction, content: system))
        }
        result.append(contentsOf: mergedPrefix)
        if let user {
            result.append(user)
        }
        result.append(contentsOf: latest)
        return result
    }

    private static func mergeByOriginalOrder(
        protected: [AgentEvent],
        pruned: [AgentEvent],
        originals: [AgentEvent]
    ) -> [AgentEvent] {
        var byID: [UUID: AgentEvent] = [:]
        for event in pruned { byID[event.id] = event }
        for event in protected { byID[event.id] = event }
        // Preserve first-seen order in `originals` without duplicates.
        var seen = Set<UUID>()
        return originals.compactMap { event in
            guard seen.insert(event.id).inserted else { return nil }
            return byID[event.id]
        }
    }

    // MARK: - Fitting

    private static func fitUser(_ event: AgentEvent?, tokenBudget: Int) -> AgentEvent? {
        guard var event else { return nil }
        guard tokenBudget > 0 else { return nil }
        let bytes = PromptBudget.utf8ByteCount(of: event)
        let maxBytes = tokenBudget * PromptBudget.bytesPerToken
        guard bytes > maxBytes else { return event }
        event.content = utf8Prefix(event.content, maxBytes: maxBytes)
            + "\n… [user message truncated to fit context budget]"
        return event
    }

    private static func truncateUser(_ event: AgentEvent?, tokenBudget: Int) -> AgentEvent? {
        fitUser(event, tokenBudget: max(tokenBudget, 1))
    }

    /// Newest-first fill. Tool-call + result blocks stay atomic; oversized results middle-out.
    private static func fitEvents(
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
                var cost = tokenCount(of: block)
                let room = tokenBudget - tokens
                if cost > room {
                    if selectedReversed.isEmpty {
                        block = shrinkToolBlock(block, tokenBudget: max(room, 1))
                        selectedReversed.append(contentsOf: block.reversed())
                    }
                    break
                }
                selectedReversed.append(contentsOf: block.reversed())
                tokens += cost
                index = blockStart - 1
                continue
            }

            if event.kind == .assistantResponse,
               let calls = event.toolCalls,
               !calls.isEmpty {
                index -= 1
                continue
            }

            let cost = PromptBudget.estimatedTokenCount(of: event)
            if tokens + cost > tokenBudget, !selectedReversed.isEmpty {
                break
            }
            if tokens + cost > tokenBudget, selectedReversed.isEmpty, forceIncludeNewest {
                if let copy = fitUser(event, tokenBudget: tokenBudget) {
                    selectedReversed.append(copy)
                    tokens += PromptBudget.estimatedTokenCount(of: copy)
                }
                break
            }
            if tokens + cost > tokenBudget {
                break
            }
            selectedReversed.append(event)
            tokens += cost
            index -= 1
        }

        return Array(selectedReversed.reversed())
    }

    private static func shrinkToolBlock(_ block: [AgentEvent], tokenBudget: Int) -> [AgentEvent] {
        let current = tokenCount(of: block)
        guard current > tokenBudget else { return block }
        let resultCount = max(block.filter { $0.kind == .toolResult }.count, 1)
        let bytesEach = max(
            (tokenBudget * PromptBudget.bytesPerToken) / resultCount,
            64
        )
        return block.map { event in
            guard event.kind == .toolResult else { return event }
            return capToolResult(event, maxUTF8Bytes: bytesEach)
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

    private static func capToolResult(_ event: AgentEvent, maxUTF8Bytes: Int) -> AgentEvent {
        guard event.kind == .toolResult else { return event }
        let body = WriteFileResultCodec.modelFacing(event.content)
        guard body.utf8.count > maxUTF8Bytes else { return event }
        var copy = event
        copy.content = middleOut(body, maxUTF8Bytes: maxUTF8Bytes)
        return copy
    }

    private static func capProtectedEvent(_ event: AgentEvent) -> AgentEvent {
        guard event.content.utf8.count > maxSkillContentCharacters else { return event }
        var copy = event
        let name = inferredSkillName(from: event.content) ?? "skill"
        copy.content = capSkillContent(event.content, skillName: name)
        return copy
    }

    private static func fitProtectedBudget(_ events: [AgentEvent], maxTokens: Int) -> [AgentEvent] {
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

    private static func looksLikeSkillPayload(_ event: AgentEvent) -> Bool {
        let content = event.content
        return content.contains("<skill_content")
            || content.contains("[Activated skill:")
            || content.contains("skill_resources")
    }

    private static func inferredSkillName(from content: String) -> String? {
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
