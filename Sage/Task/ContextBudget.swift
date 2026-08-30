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
    var capabilityReminder: String = ""
    var workPlanAppendix: String = ""
    var todoAppendix: String = ""
    var workingMemory: TaskWorkingMemory?
    var followUpAppendix: String = ""
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

    static let middleOmitMarker = "\n… [middle omitted to fit context budget]\n"
    static let skillsCatalogStub = """

    ## Available Skills
    Skill catalog omitted to stay within the context budget. Use `load_skill` if you know the name.
    """

    /// Truncates oversized skill bodies and points the model at progressive resource loading.
    static func capSkillContent(_ content: String, skillName: String) -> String {
        guard content.utf8.count > maxSkillContentCharacters else { return content }
        let head = utf8Prefix(content, maxBytes: maxSkillContentCharacters)
        return """
        \(head)

        … [skill '\(skillName)' truncated at \(maxSkillContentCharacters) characters \
        (~5k-token progressive-disclosure limit)]
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
}
