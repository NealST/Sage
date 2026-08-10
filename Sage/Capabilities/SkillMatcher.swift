//
//  SkillMatcher.swift
//  Sage
//
//  Uses the local MLX model to determine which skills are relevant
//  to the user's current input. Only matched skills are injected
//  into the system prompt — avoiding token waste on irrelevant skills.
//

import Foundation

/// Selects relevant skills for a given user message using the local model.
actor SkillMatcher {
    private let modelService: LocalModelService

    init(modelService: LocalModelService = .shared) {
        self.modelService = modelService
    }

    /// Given a user message and available skills, returns the names of skills
    /// that should be activated for this request.
    ///
    /// Falls back to returning ALL skills if the model is unavailable
    /// (preserves current behavior as a safe default).
    func match(
        userMessage: String,
        skills: [SkillRecord]
    ) async -> [String] {
        let enabled = skills.filter(\.enabled)
        guard !enabled.isEmpty else { return [] }

        // If only 1-2 skills, skip the model call — just activate them all.
        if enabled.count <= 2 {
            return enabled.map(\.name)
        }

        guard await modelService.isReady else {
            return enabled.map(\.name)
        }

        let (system, user) = Self.buildPrompt(
            userMessage: userMessage,
            skills: enabled
        )

        do {
            let output = try await modelService.generate(
                systemPrompt: system,
                userPrompt: user,
                maxTokens: 64,
                temperature: 0
            )
            let matched = Self.parse(output: output, skills: enabled)
            // If parsing fails or returns empty, fall back to all skills.
            return matched.isEmpty ? enabled.map(\.name) : matched
        } catch {
            return enabled.map(\.name)
        }
    }

    // MARK: - Prompt

    private static func buildPrompt(
        userMessage: String,
        skills: [SkillRecord]
    ) -> (system: String, user: String) {
        let system = """
        You are a skill selector. Given the user's message and a list of available skills, \
        decide which skills are relevant to the user's request.

        Rules:
        - Output a JSON object: {"skills": ["name1", "name2"]}
        - Only include skills that are directly relevant to the user's message.
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
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            return []
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(MatcherOutput.self, from: data) else {
            return []
        }

        // Validate that returned names actually exist in the skill list.
        let validNames = Set(skills.map(\.name))
        return parsed.skills.filter { validNames.contains($0) }
    }
}

// MARK: - Supporting Types

private nonisolated struct MatcherOutput: Decodable {
    let skills: [String]
}
