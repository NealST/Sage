//
//  ContextBudget+Assemble.swift
//  Sage
//

import Foundation

nonisolated extension ContextBudget {
    /// Schedules system slices and transcript events into `layout.budget.usableTokens`.
    static func assemble(_ layout: PromptLayout) -> PromptAssembly {
        let prepared = prepareAssembly(layout)
        if prepared.remaining <= 0 || prepared.totalGrow == 0 {
            return assemblePinnedOverflow(
                remaining: prepared.remaining,
                grow: prepared.growUser,
                pin: (prepared.parts.currentUser, prepared.parts.latestTurn),
                system: prepared.system,
                overflow: (prepared.pinOverflow, layout.budget.usableTokens)
            )
        }
        return assembleFlexShares(prepared.flexInput(usableTokens: layout.budget.usableTokens))
    }

    struct PreparedAssembly {
        var parts: PartitionedTranscript
        var remaining: Int
        var growUser: Int
        var growLatest: Int
        var growSkills: Int
        var totalGrow: Int
        var system: String
        var pinOverflow: Bool

        func flexInput(usableTokens: Int) -> FlexShareInput {
            FlexShareInput(
                remaining: remaining,
                growUser: growUser,
                growLatest: growLatest,
                growSkills: growSkills,
                totalGrow: totalGrow,
                currentUser: parts.currentUser,
                latestTurn: parts.latestTurn,
                history: parts.history,
                protectedSkills: parts.protectedSkills,
                prefixOrder: parts.prefixOrder,
                system: system,
                pinOverflow: pinOverflow,
                usableTokens: usableTokens
            )
        }
    }

    struct PreparedTranscript {
        var parts: PartitionedTranscript
        var memoryAppendix: String
    }

    static func prepareAssembly(_ layout: PromptLayout) -> PreparedAssembly {
        let budget = layout.budget
        let transcript = prepareTranscript(layout)
        let parts = transcript.parts
        let memoryAppendix = transcript.memoryAppendix
        var slices = SystemSliceState(
            relatedMode: .full,
            skillsCatalog: layout.skillsCatalog,
            projectAppendix: layout.projectAppendix
        )
        shrinkSystemSlices(
            layout: layout,
            memoryAppendix: memoryAppendix,
            pin: (parts.currentUser, parts.latestTurn),
            budget: budget,
            slices: &slices
        )
        let remaining = budget.usableTokens - systemSliceTokens(
            layout: layout,
            memoryAppendix: memoryAppendix,
            slices: slices
        )
        let growUser = parts.currentUser == nil ? 0 : 2
        let growLatest = parts.latestTurn.isEmpty ? 0 : 2
        let growHistory = parts.history.isEmpty ? 0 : 1
        let growSkills = parts.protectedSkills.isEmpty ? 0 : 1
        return PreparedAssembly(
            parts: parts,
            remaining: remaining,
            growUser: growUser,
            growLatest: growLatest,
            growSkills: growSkills,
            totalGrow: growUser + growLatest + growHistory + growSkills,
            system: renderSystem(
                layout: layout,
                projectAppendix: slices.projectAppendix,
                workingMemoryAppendix: memoryAppendix,
                skillsCatalog: slices.skillsCatalog,
                relatedMode: slices.relatedMode
            ),
            pinOverflow: remaining < pinTokens(user: parts.currentUser, latest: parts.latestTurn)
        )
    }

    static func prepareTranscript(_ layout: PromptLayout) -> PreparedTranscript {
        let latestUserID = layout.events.last { $0.kind == .userInput }?.id
        let withListings = layout.events.map { event in
            var copy = event.embeddingAttachmentListing(includeImagePixels: event.id == latestUserID)
            if event.id != latestUserID {
                // Historical images are represented by text stubs; do not reserve vision tokens.
                copy.attachments.removeAll { $0.kind == .image }
            }
            return copy
        }
        let sanitized = sanitize(withListings).map { event in
            capToolResult(event, maxTokens: layout.budget.maxToolResultTokens)
        }
        let memory = layout.workingMemory?.validated(against: layout.events)
        let activeMemory = (memory?.hasContent == true) ? memory : nil
        let memoryAppendix = activeMemory?.promptAppendix ?? ""
        let parts = partitionTranscript(sanitized, workingMemory: activeMemory, originalEvents: layout.events)
        return PreparedTranscript(
            parts: parts,
            memoryAppendix: memoryAppendix
        )
    }

    static func assemblePinnedOverflow(
        remaining: Int,
        grow: Int,
        pin: (user: AgentEvent?, latest: [AgentEvent]),
        system: String,
        overflow: (pin: Bool, usableTokens: Int)
    ) -> PromptAssembly {
        var remaining = remaining
        let fittedUser = remaining > 0
            ? fitUser(pin.user, tokenBudget: remaining)
            : (grow == 0 ? pin.user : truncateUser(pin.user, tokenBudget: max(remaining, 1)))
        remaining -= fittedUser.map { PromptBudget.estimatedTokenCount(of: $0) } ?? 0
        let fittedLatest = fitEvents(
            pin.latest,
            tokenBudget: max(remaining, 0),
            forceIncludeNewest: remaining > 0
        )
        remaining -= tokenCount(of: fittedLatest)
        return finish(
            events: stitch(
                PromptStitchInput(
                    system: system,
                    user: fittedUser,
                    latest: fittedLatest,
                    protected: [],
                    history: [],
                    prefixOrder: []
                )
            ),
            didExceedBudget: overflow.pin || remaining < 0,
            usableTokens: overflow.usableTokens
        )
    }

    struct FlexShareInput {
        var remaining: Int
        var growUser: Int
        var growLatest: Int
        var growSkills: Int
        var totalGrow: Int
        var currentUser: AgentEvent?
        var latestTurn: [AgentEvent]
        var history: [AgentEvent]
        var protectedSkills: [AgentEvent]
        var prefixOrder: [AgentEvent]
        var system: String
        var pinOverflow: Bool
        var usableTokens: Int
    }

    static func assembleFlexShares(_ input: FlexShareInput) -> PromptAssembly {
        func share(_ grow: Int) -> Int {
            guard input.totalGrow > 0, grow > 0 else { return 0 }
            return input.remaining * grow / input.totalGrow
        }
        let userShare = input.growUser == 0 ? 0 : max(share(input.growUser), 1)
        let latestShare = input.growLatest == 0 ? 0 : max(share(input.growLatest), 1)
        let skillsShare = share(input.growSkills)
        let (fittedUser, unusedUser) = takeFlex(
            share: userShare,
            fit: { fitUser(input.currentUser, tokenBudget: $0) },
            cost: { $0.map { PromptBudget.estimatedTokenCount(of: $0) } ?? 0 }
        )
        let (fittedLatest, unusedLatest) = takeFlex(
            share: latestShare,
            fit: { fitEvents(input.latestTurn, tokenBudget: $0, forceIncludeNewest: true) },
            cost: { tokenCount(of: $0) }
        )
        let (fittedSkills, unusedSkills) = takeFlex(
            share: skillsShare,
            fit: { tokens in
                tokens > 0 ? fitProtectedBudget(input.protectedSkills, maxTokens: tokens) : []
            },
            cost: { tokenCount(of: $0) }
        )
        let historyBudget = max(input.remaining - userShare - latestShare - skillsShare, 0)
            + unusedUser + unusedLatest + unusedSkills
        return finish(
            events: stitch(
                PromptStitchInput(
                    system: input.system,
                    user: fittedUser,
                    latest: fittedLatest,
                    protected: fittedSkills,
                    history: fitEvents(input.history, tokenBudget: historyBudget, forceIncludeNewest: false),
                    prefixOrder: input.prefixOrder
                )
            ),
            didExceedBudget: input.pinOverflow,
            usableTokens: input.usableTokens
        )
    }

    static func finish(
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

    static func takeFlex<T>(
        share: Int,
        fit: (Int) -> T,
        cost: (T) -> Int
    ) -> (T, unused: Int) {
        let fitted = fit(max(share, 0))
        let used = cost(fitted)
        return (fitted, max(share - used, 0))
    }

    struct PartitionedTranscript {
        var currentUser: AgentEvent?
        var latestTurn: [AgentEvent]
        var history: [AgentEvent]
        var protectedSkills: [AgentEvent]
        var prefixOrder: [AgentEvent]
    }

    static func partitionTranscript(
        _ sanitized: [AgentEvent],
        workingMemory: TaskWorkingMemory?,
        originalEvents: [AgentEvent]
    ) -> PartitionedTranscript {
        let lastUser = sanitized.last { $0.kind == .userInput && !$0.protected }
        let lastUserID = lastUser?.id
        let lastUserIndex = lastUser.flatMap { user in
            sanitized.firstIndex { $0.id == user.id }
        }
        var folded = Set(workingMemory?.foldedEventIDs(in: originalEvents) ?? [])
        if let lastUserID {
            folded.remove(lastUserID)
        }

        var parts = PartitionedTranscript(
            currentUser: nil,
            latestTurn: [],
            history: [],
            protectedSkills: [],
            prefixOrder: []
        )
        for (index, event) in sanitized.enumerated() {
            if folded.contains(event.id) { continue }
            if let lastUserIndex, index > lastUserIndex {
                parts.latestTurn.append(event)
                continue
            }
            if event.id == lastUserID {
                parts.currentUser = event
                continue
            }
            if event.protected {
                let capped = capProtectedEvent(event)
                parts.protectedSkills.append(capped)
                parts.prefixOrder.append(capped)
                continue
            }
            parts.history.append(event)
            parts.prefixOrder.append(event)
        }
        return parts
    }

    static func pinTokens(user: AgentEvent?, latest: [AgentEvent]) -> Int {
        (user.map { PromptBudget.estimatedTokenCount(of: $0) } ?? 0) + tokenCount(of: latest)
    }

    struct SystemSliceState {
        var relatedMode: RelatedRenderMode
        var skillsCatalog: String
        var projectAppendix: String
    }

    static func systemSliceTokens(
        layout: PromptLayout,
        memoryAppendix: String,
        slices: SystemSliceState
    ) -> Int {
        tokenCount(in: [
            layout.baseInstructions,
            layout.capabilityReminder,
            layout.workPlanAppendix,
            layout.todoAppendix,
            memoryAppendix,
            layout.followUpAppendix,
            slices.projectAppendix,
            slices.skillsCatalog,
            renderRelated(layout.relatedSnippets, mode: slices.relatedMode),
        ])
    }

    static func shrinkSystemSlices(
        layout: PromptLayout,
        memoryAppendix: String,
        pin: (user: AgentEvent?, latest: [AgentEvent]),
        budget: PromptBudget,
        slices: inout SystemSliceState
    ) {
        func overflow() -> Bool {
            systemSliceTokens(
                layout: layout,
                memoryAppendix: memoryAppendix,
                slices: slices
            ) + pinTokens(user: pin.user, latest: pin.latest) > budget.usableTokens
        }
        if overflow() { slices.relatedMode = .titles }
        if overflow() { slices.relatedMode = .omitted }
        if overflow(), !slices.skillsCatalog.isEmpty {
            slices.skillsCatalog = skillsCatalogStub
        }
        if overflow(), slices.projectAppendix.utf8.count > 1_200 {
            let cap = max(budget.usableTokens / 8, 200) * PromptBudget.bytesPerToken
            slices.projectAppendix = middleOut(slices.projectAppendix, maxUTF8Bytes: cap)
        }
    }

    static func tokenCount(in texts: [String]) -> Int {
        texts.reduce(0) { $0 + PromptBudget.estimatedTokenCount(in: $1) }
    }

    static func tokenCount(of events: [AgentEvent]) -> Int {
        events.reduce(0) { $0 + PromptBudget.estimatedTokenCount(of: $1) }
    }
}
