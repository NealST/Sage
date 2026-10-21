import Foundation

/// A skill candidate surfaced by local recall (activation choice or consolidate tip).
nonisolated struct SkillRecallCandidate: Identifiable, Equatable, Sendable, Hashable {
    var id: String { path }

    let name: String
    let description: String
    let path: String
    let scope: SkillScope

    init(skill: SkillRecord) {
        name = skill.name
        description = skill.description
        path = skill.path
        scope = skill.scope
    }

    init(name: String, description: String, path: String, scope: SkillScope) {
        self.name = name
        self.description = description
        self.path = path
        self.scope = scope
    }
}

/// Paused turn: user must pick one overlapping skill (or skip) before the agent continues.
nonisolated struct SkillActivationChoice: Equatable, Sendable {
    let id: UUID
    let candidates: [SkillRecallCandidate]
    /// Message or plan-step text used for matching.
    let queryText: String

    init(
        id: UUID = UUID(),
        candidates: [SkillRecallCandidate],
        queryText: String
    ) {
        self.id = id
        self.candidates = candidates
        self.queryText = queryText
    }
}

/// Quality signal: multiple skills matched the same intent — offer merge / rewrite.
nonisolated struct SkillConsolidateSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let candidates: [SkillRecallCandidate]
    /// Which candidate path to keep when merging (defaults to first).
    let primaryPath: String

    init(
        id: UUID = UUID(),
        candidates: [SkillRecallCandidate],
        primaryPath: String? = nil
    ) {
        self.id = id
        self.candidates = candidates
        self.primaryPath = primaryPath ?? candidates.first?.path ?? ""
    }

    var primary: SkillRecallCandidate? {
        candidates.first { $0.path == primaryPath } ?? candidates.first
    }

    /// Returns a copy with an explicit keep target (after the user chooses in the tip).
    func resolved(primaryPath: String) -> Self {
        Self(
            id: id,
            candidates: candidates,
            primaryPath: primaryPath
        )
    }
}
