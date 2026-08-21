//
//  SkillExtractionService.swift
//  Sage
//
//  Analyzes completed tasks to identify reusable experiences worth saving as skills.
//  Extraction only decides skip / new / enhance; full SKILL.md content is composed
//  after the user confirms the banner suggestion.
//

import Foundation

/// How skill extraction was triggered.
nonisolated enum SkillExtractionMode: Sendable {
    /// Passive close-task extraction — may return skip.
    case automatic
    /// User explicitly asked to remember (`/remember`) — must choose new or enhance.
    case explicitRemember
}

/// Result of skill extraction analysis (identification only — no full body yet).
nonisolated enum SkillExtractionResult: Sendable, Equatable {
    /// The task does not contain experience worth saving.
    case skip
    /// A new skill should be created.
    case newSkill(name: String, description: String)
    /// An existing skill should be enhanced with new knowledge.
    case enhance(existingName: String, description: String)
}

/// Draft produced when composing a skill after user confirmation.
nonisolated struct SkillDraft: Sendable {
    let description: String
    let body: String
}

nonisolated struct SkillMergeInput: Sendable {
    let name: String
    let description: String
    let body: String
}

nonisolated enum SkillCompositionError: LocalizedError {
    case emptyTranscript
    case sourceTaskMissing
    case modelFailed(String)
    case invalidResponse
    case unsupportedMergeViaSuggestion
    case mergeCleanupFailed([String])
    case hostUnavailable
    case sessionTornDown

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Source task has no usable transcript to compose from."

        case .sourceTaskMissing:
            return "Source task is no longer available; cannot save this skill."

        case .modelFailed(let message):
            return "Could not compose skill: \(message)"

        case .invalidResponse:
            return "Model returned an invalid skill draft."

        case .unsupportedMergeViaSuggestion:
            return "Merge suggestions must use the consolidate flow."

        case .mergeCleanupFailed(let names):
            return "Merged skill saved, but couldn’t move to Trash: \(names.joined(separator: ", "))."

        case .hostUnavailable:
            return "Could not save skill — the workspace is no longer available."

        case .sessionTornDown:
            return "Could not save skill — the window was closed."
        }
    }
}

/// Extracts reusable experiences from completed tasks via cloud model analysis.
actor SkillExtractionService {
    let modelClient: ModelClient

    init(modelClient: ModelClient = ModelClient()) {
        self.modelClient = modelClient
    }

    /// Analyzes a completed task to determine if it contains reusable experience.
    ///
    /// Identification only — does not generate full skill bodies. Composition runs
    /// after the user confirms the banner suggestion.
    ///
    /// - Parameters:
    ///   - task: The completed TaskRecord with full event history.
    ///   - existingSkills: Current skill catalog summaries for deduplication (no bodies).
    ///   - settings: Model settings snapshot (captured on MainActor before calling).
    ///   - mode: `.automatic` may skip; `.explicitRemember` must return new or enhance.
    ///   - userNote: Optional hint from `/remember …` (explicit mode only).
    ///   - preferredEnhanceTargets: Optional names to bias analyze toward enhance.
    /// - Returns: Extraction result indicating skip, new skill, or enhancement.
    func analyze(
        task: TaskRecord,
        existingSkills: [SkillCatalogSummary],
        settings: ModelSettingsSnapshot,
        mode: SkillExtractionMode = .automatic,
        userNote: String? = nil,
        preferredEnhanceTargets: [String] = []
    ) async -> SkillExtractionResult? {
        let transcript = buildTranscript(from: task)
        guard !transcript.isEmpty else { return nil }
        let events = extractionPromptEvents(
            ExtractionPromptInput(
                task: task,
                transcript: transcript,
                existingSkills: existingSkills,
                mode: mode,
                userNote: userNote,
                preferredEnhanceTargets: preferredEnhanceTargets
            )
        )
        let catalogNames = Set(existingSkills.map(\.name))

        do {
            let turn = try await modelClient.complete(
                events: events,
                tools: [],
                settings: settings,
                retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1.0, maxDelay: 10.0)
            )

            guard let content = turn.content else {
                return mode == .explicitRemember ? nil : .skip
            }
            let parsed = SkillExtractionParsing.reconcile(
                parseResponse(content),
                catalogNames: catalogNames,
                preferredTargets: preferredEnhanceTargets
            )
            // Explicit remember must not soft-skip; treat skip as failure for retry UX.
            if mode == .explicitRemember, case .skip = parsed {
                return nil
            }
            return parsed
        } catch {
            return nil
        }
    }

    struct ExtractionPromptInput {
        var task: TaskRecord
        var transcript: String
        var existingSkills: [SkillCatalogSummary]
        var mode: SkillExtractionMode
        var userNote: String?
        var preferredEnhanceTargets: [String]
    }

    func extractionPromptEvents(_ input: ExtractionPromptInput) -> [AgentEvent] {
        let preferredSet = Set(input.preferredEnhanceTargets)
        let skillLines = input.existingSkills.map { skill in
            let mark = preferredSet.contains(skill.name) ? " ← preferred enhance target" : ""
            return "- \(skill.name) [\(skill.scope.catalogLabel)]: \(skill.description)\(mark)"
        }
        let skillsCatalog = skillLines.joined(separator: "\n")
        let systemPrompt: String
        switch input.mode {
        case .automatic:
            systemPrompt = SkillExtractionPrompts.automaticSystemPrompt(
                skillsCatalog: skillsCatalog,
                preferredEnhanceTargets: input.preferredEnhanceTargets
            )

        case .explicitRemember:
            systemPrompt = SkillExtractionPrompts.explicitRememberSystemPrompt(
                skillsCatalog: skillsCatalog,
                preferredEnhanceTargets: input.preferredEnhanceTargets
            )
        }
        var userPrompt = """
        ## Task Summary
        \(input.task.topic ?? input.task.summary ?? "Untitled task")

        ## Task Transcript
        \(input.transcript)
        """
        if input.mode == .explicitRemember,
           let note = input.userNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            userPrompt += """


            ## User note
            The user added this hint with /remember: \(note)
            """
        }
        return [
            AgentEvent(kind: .systemInstruction, content: systemPrompt),
            AgentEvent(kind: .userInput, content: userPrompt),
        ]
    }

    /// Composes a new skill from task knowledge after the user confirms a banner suggestion.
    func composeNewSkill(
        skillName: String,
        suggestedDescription: String,
        task: TaskRecord,
        settings: ModelSettingsSnapshot
    ) async throws -> SkillDraft {
        let transcript = try requireTranscript(from: task)
        let systemPrompt = SkillExtractionPrompts.authoringSystemPrompt(
            role: "skill author",
            mission: "Turn reusable knowledge from a completed task into a clear, durable skill document.",
            goals: """
            - Capture non-obvious procedures, gotchas, and workflows from the task transcript.
            - Omit trivia and widely known information.
            - Follow the skill writing best practices below (same standards as the save_skill tool).
            """,
            descriptionField: "One-sentence description"
        )
        let userPrompt = """
        ## New skill
        Name: \(skillName)
        Suggested description (from earlier analysis — revise if needed): \(suggestedDescription)

        ## Source task
        Summary: \(task.topic ?? task.summary ?? "Untitled task")

        ## Task transcript
        \(transcript)
        """
        return try await completeCompose(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            settings: settings
        )
    }

    /// Composes an enhanced skill by merging the existing skill with new task knowledge,
    /// following `save_skill` authoring best practices.
    ///
    /// Called after the user confirms an enhance suggestion in the banner.
    func composeEnhancedSkill(_ input: SkillEnhanceInput) async throws -> SkillDraft {
        let skillName = input.skillName
        let currentDescription = input.currentDescription
        let currentBody = input.currentBody
        let suggestedDescription = input.suggestedDescription
        let task = input.task
        let settings = input.settings
        let transcript = try requireTranscript(from: task)
        let systemPrompt = SkillExtractionPrompts.authoringSystemPrompt(
            role: "skill editor",
            mission: """
            Merge an existing skill with new knowledge from a completed task \
            into one coherent, improved skill document.
            """,
            goals: """
            - Treat the existing skill as the cumulative experience document across prior tasks.
            - Preserve durable, still-correct guidance from the existing skill.
            - Fold in new non-obvious knowledge from this task (edge cases, corrections, better steps).
            - When the new transcript contradicts the old skill, prefer the newer evidence and drop the stale guidance.
            - Deduplicate overlapping procedures; keep one clear path per situation.
            - Follow the skill writing best practices below (same standards as the save_skill tool).
            """,
            descriptionField: "Updated one-sentence description"
        )
        let userPrompt = """
        ## Target skill
        Name: \(skillName)
        Current description: \(currentDescription)
        Suggested description (from earlier analysis — revise if needed): \(suggestedDescription)

        ## Existing skill body
        \(currentBody.isEmpty ? "(empty)" : currentBody)

        ## Source task
        Summary: \(task.topic ?? task.summary ?? "Untitled task")

        ## Task transcript (new knowledge)
        \(transcript)
        """
        return try await completeCompose(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            settings: settings
        )
    }

    /// Merges several overlapping skills into one coherent document (quality / consolidate tip).
    func composeMergedSkills(
        primaryName: String,
        skills: [SkillMergeInput],
        settings: ModelSettingsSnapshot
    ) async throws -> SkillDraft {
        guard skills.count >= 2 else {
            throw SkillCompositionError.invalidResponse
        }

        let systemPrompt = SkillExtractionPrompts.authoringSystemPrompt(
            role: "skill editor",
            mission: """
            Several skills appear to cover the same intent. Merge them into \
            ONE cohesive skill that keeps the best guidance from each and removes duplication.
            """,
            goals: """
            - Prefer the clearest, most actionable procedures.
            - Resolve contradictions by keeping the more specific / safer guidance.
            - The merged description must clearly state when to use this skill so it won't \
              overlap with unrelated skills in the catalog.
            - Follow the skill writing best practices below (same standards as enhance / save_skill).
            """,
            descriptionField: "One-sentence description"
        )

        var sections: [String] = [
            "## Target merged skill name",
            primaryName,
            "",
            "## Skills to merge",
        ]
        for (index, skill) in skills.enumerated() {
            sections.append("""
            ### \(index + 1). \(skill.name)
            Description: \(skill.description)

            Body:
            \(skill.body.isEmpty ? "(empty)" : skill.body)
            """)
        }

        return try await completeCompose(
            systemPrompt: systemPrompt,
            userPrompt: sections.joined(separator: "\n"),
            settings: settings
        )
    }
}
