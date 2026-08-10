//
//  SkillMatcher.swift
//  Sage
//
//  Implements progressive skill activation:
//  1. Local model available → selects relevant skills, injects their full body
//  2. Local model unavailable → injects only the skill catalog (name + description)
//     into the system prompt; the cloud model uses `load_skill` tool to fetch bodies
//
//  Skills are NEVER all injected at once. Only matched/requested skills are loaded.
//

import Foundation

/// Result of skill matching — determines how skills are presented to the cloud model.
enum SkillMatchResult: Sendable {
    /// Local model selected specific skills — inject their full body.
    case resolved(names: [String])
    /// Local model unavailable — inject catalog only, cloud model decides via tool.
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

        guard await modelService.isReady else {
            return .deferred
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

        let validNames = Set(skills.map(\.name))
        return parsed.skills.filter { validNames.contains($0) }
    }
}

// MARK: - Supporting Types

private nonisolated struct MatcherOutput: Decodable {
    let skills: [String]
}
