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
enum SkillExtractionMode: Sendable {
    /// Passive close-task extraction — may return skip.
    case automatic
    /// User explicitly asked to remember (`/remember`) — must choose new or enhance.
    case explicitRemember
}

/// Result of skill extraction analysis (identification only — no full body yet).
enum SkillExtractionResult: Sendable, Equatable {
    /// The task does not contain experience worth saving.
    case skip
    /// A new skill should be created.
    case newSkill(name: String, description: String)
    /// An existing skill should be enhanced with new knowledge.
    case enhance(existingName: String, description: String)
}

/// Draft produced when composing a skill after user confirmation.
struct SkillDraft: Sendable {
    let description: String
    let body: String
}

enum SkillCompositionError: LocalizedError {
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
    private let modelClient: ModelClient

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
    ///   - preferredEnhanceTargets: Local-matcher neighbors; biases analyze toward enhance.
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

        let preferredSet = Set(preferredEnhanceTargets)
        let skillsCatalog = existingSkills.map { skill in
            let mark = preferredSet.contains(skill.name) ? " ← preferred enhance target" : ""
            return "- \(skill.name) [\(skill.scope.catalogLabel)]: \(skill.description)\(mark)"
        }.joined(separator: "\n")

        let systemPrompt: String
        switch mode {
        case .automatic:
            systemPrompt = SkillExtractionPrompts.automaticSystemPrompt(
                skillsCatalog: skillsCatalog,
                preferredEnhanceTargets: preferredEnhanceTargets
            )
        case .explicitRemember:
            systemPrompt = SkillExtractionPrompts.explicitRememberSystemPrompt(
                skillsCatalog: skillsCatalog,
                preferredEnhanceTargets: preferredEnhanceTargets
            )
        }

        var userPrompt = """
        ## Task Summary
        \(task.topic ?? task.summary ?? "Untitled task")

        ## Task Transcript
        \(transcript)
        """
        if mode == .explicitRemember,
           let note = userNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            userPrompt += """


            ## User note
            The user added this hint with /remember: \(note)
            """
        }

        let events: [AgentEvent] = [
            AgentEvent(kind: .systemInstruction, content: systemPrompt),
            AgentEvent(kind: .userInput, content: userPrompt),
        ]

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
    func composeEnhancedSkill(
        skillName: String,
        currentDescription: String,
        currentBody: String,
        suggestedDescription: String,
        task: TaskRecord,
        settings: ModelSettingsSnapshot
    ) async throws -> SkillDraft {
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
        skills: [(name: String, description: String, body: String)],
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

    // MARK: - Composition Helpers

    private func requireTranscript(from task: TaskRecord) throws -> String {
        let transcript = buildTranscript(from: task)
        guard !transcript.isEmpty else {
            throw SkillCompositionError.emptyTranscript
        }
        return transcript
    }


    private func completeCompose(
        systemPrompt: String,
        userPrompt: String,
        settings: ModelSettingsSnapshot
    ) async throws -> SkillDraft {
        let events: [AgentEvent] = [
            AgentEvent(kind: .systemInstruction, content: systemPrompt),
            AgentEvent(kind: .userInput, content: userPrompt),
        ]

        do {
            let turn = try await modelClient.complete(
                events: events,
                tools: [],
                settings: settings,
                retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1.0, maxDelay: 10.0)
            )
            guard let content = turn.content else {
                throw SkillCompositionError.invalidResponse
            }
            return try parseComposeResponse(content)
        } catch let error as SkillCompositionError {
            throw error
        } catch {
            throw SkillCompositionError.modelFailed(error.localizedDescription)
        }
    }

    // MARK: - Transcript Building

    /// Extracts a concise transcript from task events, focusing on key interactions.
    private func buildTranscript(from task: TaskRecord) -> String {
        var lines: [String] = []
        var totalLength = 0
        let maxLength = 6000
        let separatorLength = 1 // "\n"

        for event in task.events {
            let prefix: String
            switch event.kind {
            case .userInput:
                prefix = "User"
            case .assistantResponse:
                prefix = "Assistant"
            case .toolResult:
                prefix = "Tool Result"
            case .systemInstruction:
                continue
            }

            let contentPreview: String
            if event.kind == .toolResult && event.content.count > 500 {
                contentPreview = String(event.content.prefix(500)) + "…[truncated]"
            } else {
                contentPreview = event.content
            }

            let line: String
            if let toolCalls = event.toolCalls, !toolCalls.isEmpty {
                let callSummaries = toolCalls.map { "[\($0.name)]" }.joined(separator: ", ")
                line = "\(prefix) (calls: \(callSummaries)): \(contentPreview)"
            } else {
                line = "\(prefix): \(contentPreview)"
            }

            if !lines.isEmpty {
                totalLength += separatorLength
            }
            lines.append(line)
            totalLength += line.count

            if totalLength > maxLength {
                let keep = max(lines.count / 2, 1)
                let dropped = lines.prefix(lines.count - keep)
                let droppedLength = dropped.reduce(0) { $0 + $1.count } + dropped.count * separatorLength
                lines = Array(lines.suffix(keep))
                let marker = "[...earlier conversation truncated...]"
                lines.insert(marker, at: 0)
                totalLength = totalLength - droppedLength + marker.count + separatorLength
            }
        }

        return lines.joined(separator: "\n")
    }

    private func parseResponse(_ content: String) -> SkillExtractionResult {
        SkillExtractionParsing.parseResponse(content)
    }

    private func parseComposeResponse(_ content: String) throws -> SkillDraft {
        try SkillExtractionParsing.parseComposeResponse(content)
    }

}
