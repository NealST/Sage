import Foundation

/// Result of skill matching — determines whether skills are auto-loaded or deferred to the cloud model.
nonisolated enum SkillMatchResult: Sendable {
    /// Local model selected specific skills (0…N). Runtime auto-loads only when count == 1;
    /// count >= 2 pauses for user choice and may surface a consolidate tip.
    case resolved(names: [String])
    /// Local model unavailable — cloud model decides via `load_skill` tool.
    case deferred
}

/// Selects relevant skills for a given user message using the local model.
actor SkillMatcher {
    private let modelService: LocalModelService

    init(modelService: LocalModelService = .shared) {
        self.modelService = modelService
    }

    /// Attempts to match skills using the local model.
    /// Returns `.resolved` with matched skill names, or `.deferred` if the model
    /// is unavailable (cloud model will decide via `load_skill` tool).
    func match(
        userMessage: String,
        skills: [SkillRecord]
    ) async -> SkillMatchResult {
        let enabled = skills.filter(\.enabled)
        guard !enabled.isEmpty else { return .resolved(names: []) }

        // Skills that opt out of local model matching are excluded from the
        // candidate list but still available via the `load_skill` tool.
        let candidates = enabled.filter { !$0.disableModelInvocation }

        guard await modelService.isReady else {
            return .deferred
        }

        guard !candidates.isEmpty else {
            // All enabled skills opted out of model invocation — defer to cloud.
            return .deferred
        }

        let (system, user) = Self.buildPrompt(
            userMessage: userMessage,
            skills: candidates
        )

        do {
            let output = try await modelService.generate(
                systemPrompt: system,
                userPrompt: user,
                maxTokens: 96,
                temperature: 0
            )
            let matched = Self.parse(output: output, skills: candidates)
            return .resolved(names: matched)
        } catch {
            return .deferred
        }
    }

    // MARK: - Prompt

    private static func buildPrompt(
        userMessage: String,
        skills: [SkillRecord]
    ) -> (system: String, user: String) {
        let system = """
        You are a skill selector. Given the user's message and a list of available skills, \
        decide which skills match the user's intent.

        Ideal skills are independent and cohesive — a clear intent usually matches ZERO or ONE skill.

        Rules:
        - Output a JSON object: {"skills": ["name1", "name2"]}
        - Include a skill only when its description clearly matches the user's intent.
        - If several skills overlap on the SAME intent, include all of them \
          (the app will ask the user which to use, and may suggest merging).
        - Do NOT include tangentially related skills.
        - If no skills are relevant, output: {"skills": []}
        - Output ONLY the JSON object, nothing else.
        """

        let catalog = skills.enumerated().map { index, skill in
            "\(index + 1). \(skill.name): \(skill.description)"
        }.joined(separator: "\n")

        let user = """
        Available skills:
        \(catalog)

        User message: \(String(userMessage.prefix(500)))
        """

        return (system, user)
    }

    // MARK: - Parsing

    private static func parse(
        output: String,
        skills: [SkillRecord]
    ) -> [String] {
        guard let parsed = ModelJSONSlice.decode(MatcherOutput.self, from: output) else {
            return []
        }

        let validNames = Set(skills.map(\.name))
        // Preserve model order; drop unknowns / duplicates.
        var seen = Set<String>()
        var ordered: [String] = []
        for name in parsed.skills where validNames.contains(name) && seen.insert(name).inserted {
            ordered.append(name)
        }
        return ordered
    }
}

// MARK: - Supporting Types

private nonisolated struct MatcherOutput: Decodable, Sendable {
    let skills: [String]
}
