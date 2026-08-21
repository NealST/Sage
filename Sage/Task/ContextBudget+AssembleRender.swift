//
//  ContextBudget+AssembleRender.swift
//  Sage
//

import Foundation

nonisolated extension ContextBudget {
    enum RelatedRenderMode {
        case full
        case titles
        case omitted
    }

    static func renderSystem(
        layout: PromptLayout,
        projectAppendix: String,
        workingMemoryAppendix: String,
        skillsCatalog: String,
        relatedMode: RelatedRenderMode
    ) -> String {
        [
            layout.baseInstructions,
            projectAppendix,
            layout.capabilityReminder,
            layout.workPlanAppendix,
            layout.todoAppendix,
            workingMemoryAppendix,
            layout.reviewFeedback,
            skillsCatalog,
            renderRelated(layout.relatedSnippets, mode: relatedMode),
        ]
        .filter { !$0.isEmpty }
        .joined()
    }

    static func renderRelated(
        _ snippets: [RelatedTaskContextSnippet],
        mode: RelatedRenderMode
    ) -> String {
        guard mode != .omitted, !snippets.isEmpty else { return "" }
        var lines = ["", "## Related prior work", "Use only if relevant to the current request:"]
        for related in snippets {
            appendRelatedSnippet(&lines, related, mode: mode)
        }
        return lines.count > 3 ? lines.joined(separator: "\n") : ""
    }

    static func appendRelatedSnippet(
        _ lines: inout [String],
        _ related: RelatedTaskContextSnippet,
        mode: RelatedRenderMode
    ) {
        let topic = related.topic?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let summary = related.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        lines.append("- \(topic ?? summary ?? "Prior task")")
        if let abstract = related.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
           !abstract.isEmpty {
            lines.append("  Intent: \(abstract)")
        }
        guard mode == .full else { return }
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

    static func stitch(_ input: PromptStitchInput) -> [AgentEvent] {
        let mergedPrefix = mergeByOriginalOrder(
            protected: input.protected,
            pruned: input.history,
            originals: input.prefixOrder
        )
        var result: [AgentEvent] = []
        if !input.system.isEmpty {
            result.append(AgentEvent(kind: .systemInstruction, content: input.system))
        }
        result.append(contentsOf: mergedPrefix)
        if let user = input.user {
            result.append(user)
        }
        result.append(contentsOf: input.latest)
        return result
    }

    static func mergeByOriginalOrder(
        protected: [AgentEvent],
        pruned: [AgentEvent],
        originals: [AgentEvent]
    ) -> [AgentEvent] {
        var byID: [UUID: AgentEvent] = [:]
        for event in pruned { byID[event.id] = event }
        for event in protected { byID[event.id] = event }
        var seen = Set<UUID>()
        return originals.compactMap { event in
            guard seen.insert(event.id).inserted else { return nil }
            return byID[event.id]
        }
    }
}
