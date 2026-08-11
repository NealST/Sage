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
enum SkillExtractionResult: Sendable {
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
    ///   - existingSkills: Current skill catalog (name, description, and body) for deduplication.
    ///   - settings: Model settings snapshot (captured on MainActor before calling).
    ///   - mode: `.automatic` may skip; `.explicitRemember` must return new or enhance.
    ///   - userNote: Optional hint from `/remember …` (explicit mode only).
    /// - Returns: Extraction result indicating skip, new skill, or enhancement.
    func analyze(
        task: TaskRecord,
        existingSkills: [(name: String, description: String, body: String, scope: SkillScope)],
        settings: ModelSettingsSnapshot,
        mode: SkillExtractionMode = .automatic,
        userNote: String? = nil
    ) async -> SkillExtractionResult? {

        let transcript = buildTranscript(from: task)
        guard !transcript.isEmpty else { return nil }

        let skillsCatalog = existingSkills.map { skill in
            var entry = "- \(skill.name) [\(skill.scope.catalogLabel)]: \(skill.description)"
            if !skill.body.isEmpty {
                let preview = String(skill.body.prefix(300))
                entry += "\n  Current content: \(preview)\(skill.body.count > 300 ? "…" : "")"
            }
            return entry
        }.joined(separator: "\n")

        let systemPrompt: String
        switch mode {
        case .automatic:
            systemPrompt = Self.automaticSystemPrompt(skillsCatalog: skillsCatalog)
        case .explicitRemember:
            systemPrompt = Self.explicitRememberSystemPrompt(skillsCatalog: skillsCatalog)
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
            let parsed = parseResponse(content, mode: mode)
            // Explicit remember must not soft-skip; treat skip as failure for retry UX.
            if mode == .explicitRemember, case .skip = parsed {
                return nil
            }
            return parsed
        } catch {
            return nil
        }
    }

    private static func automaticSystemPrompt(skillsCatalog: String) -> String {
        """
        You are an experience analyst. Your job is to examine a completed task conversation \
        and determine if it contains reusable knowledge worth saving as a "skill" (a reusable \
        instruction/experience document).

        A skill is worth saving when the task involved:
        - A non-obvious workaround or solution to a tricky problem
        - A best practice discovered through trial and error
        - A useful workflow or pattern that could apply to similar future tasks
        - Domain-specific knowledge that was hard to figure out

        A skill is NOT worth saving when:
        - The task was trivial or routine (simple Q&A, basic file operations)
        - The knowledge is too specific to one situation with no reuse potential
        - The information is widely known and easily searchable

        Existing skills are labeled [global] or [project]. Prefer enhancing an existing skill \
        when the new knowledge belongs with it; do not invent a near-duplicate name.

        ## Existing Skills
        \(skillsCatalog.isEmpty ? "(none)" : skillsCatalog)

        ## Response Format
        Respond with ONLY a JSON object in one of these formats:

        If not worth saving:
        {"action": "skip", "reason": "brief explanation"}

        If a new skill should be created:
        {"action": "new", "name": "kebab-case-name", "description": "One sentence description of when to use the skill"}

        If an existing skill should be enhanced:
        {"action": "enhance", "target": "existing-skill-name", "description": "Updated one-sentence description of when to use the skill"}

        Do NOT generate the full skill body — it will be composed later when the user confirms, \
        using the task transcript (and for enhance, the existing skill text) plus skill writing best practices.

        Output ONLY the JSON object, nothing else.
        """
    }

    private static func explicitRememberSystemPrompt(skillsCatalog: String) -> String {
        """
        You are an experience analyst. The user explicitly asked to remember knowledge from \
        this task as a skill. You MUST choose either a new skill or an enhancement — do not skip.

        Decide:
        - "enhance" when the knowledge belongs with an existing skill (same problem class / domain).
        - "new" when it is a distinct reusable topic with no good existing target.

        Existing skills are labeled [global] or [project]. Prefer enhancing when appropriate; \
        do not invent a near-duplicate name.

        ## Existing Skills
        \(skillsCatalog.isEmpty ? "(none)" : skillsCatalog)

        ## Response Format
        Respond with ONLY a JSON object in one of these formats:

        If a new skill should be created:
        {"action": "new", "name": "kebab-case-name", "description": "One sentence description of when to use the skill"}

        If an existing skill should be enhanced:
        {"action": "enhance", "target": "existing-skill-name", "description": "Updated one-sentence description of when to use the skill"}

        Do NOT use action "skip". Do NOT generate the full skill body — it will be composed later \
        when the user confirms.

        Output ONLY the JSON object, nothing else.
        """
    }

    /// Composes a new skill from task knowledge after the user confirms a banner suggestion.
    func composeNewSkill(
        skillName: String,
        suggestedDescription: String,
        task: TaskRecord,
        settings: ModelSettingsSnapshot
    ) async throws -> SkillDraft {
        let transcript = buildTranscript(from: task)
        guard !transcript.isEmpty else {
            throw SkillCompositionError.emptyTranscript
        }

        let systemPrompt = """
        You are a skill author. Turn reusable knowledge from a completed task into a clear, \
        durable skill document.

        ## Goals
        - Capture non-obvious procedures, gotchas, and workflows from the task transcript.
        - Omit trivia and widely known information.
        - Follow the skill writing best practices below (same standards as the save_skill tool).

        ## Skill writing best practices
        Description: \(SkillAuthoring.descriptionGuidelines)

        Body: \(SkillAuthoring.bodyGuidelines)

        ## Response Format
        Respond with ONLY a JSON object:
        {"description": "One-sentence description", "body": "Full skill markdown body without frontmatter"}

        Output ONLY the JSON object, nothing else.
        """

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
        let transcript = buildTranscript(from: task)
        guard !transcript.isEmpty else {
            throw SkillCompositionError.emptyTranscript
        }

        let systemPrompt = """
        You are a skill editor. Merge an existing skill with new knowledge from a completed task \
        into one coherent, improved skill document.

        ## Goals
        - Preserve durable, still-correct guidance from the existing skill.
        - Integrate new non-obvious knowledge from the task transcript.
        - Remove outdated, duplicated, or contradicted guidance (prefer the newer task evidence).
        - Follow the skill writing best practices below (same standards as the save_skill tool).

        ## Skill writing best practices
        Description: \(SkillAuthoring.descriptionGuidelines)

        Body: \(SkillAuthoring.bodyGuidelines)

        ## Response Format
        Respond with ONLY a JSON object:
        {"description": "Updated one-sentence description", "body": "Full skill markdown body without frontmatter"}

        Output ONLY the JSON object, nothing else.
        """

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

    // MARK: - Composition Helpers

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
        let maxLength = 6000 // Cap transcript to avoid excessive token usage

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
                continue // Skip system instructions
            }

            // Truncate individual event content to avoid a single large tool result
            // consuming the entire budget.
            let contentPreview: String
            if event.kind == .toolResult && event.content.count > 500 {
                contentPreview = String(event.content.prefix(500)) + "…[truncated]"
            } else {
                contentPreview = event.content
            }

            // Include tool call info if present
            if let toolCalls = event.toolCalls, !toolCalls.isEmpty {
                let callSummaries = toolCalls.map { "[\($0.name)]" }.joined(separator: ", ")
                lines.append("\(prefix) (calls: \(callSummaries)): \(contentPreview)")
            } else {
                lines.append("\(prefix): \(contentPreview)")
            }

            let current = lines.joined(separator: "\n")
            if current.count > maxLength {
                // Truncate early events, keep recent ones
                lines = Array(lines.suffix(lines.count / 2))
                lines.insert("[...earlier conversation truncated...]", at: 0)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Response Parsing

    /// Normalizes a model-generated skill name to valid kebab-case.
    /// Converts spaces/underscores to hyphens, lowercases, strips invalid chars.
    private static func normalizeSkillName(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var collapsed: [Character] = []
        for char in lowered {
            let mapped: Character
            if char.isASCII && (char.isLowercase || char.isNumber) {
                mapped = char
            } else if char == "-" || char == "_" || char == " " {
                mapped = "-"
            } else {
                continue
            }
            if mapped == "-" && collapsed.last == "-" { continue }
            collapsed.append(mapped)
        }

        while collapsed.first == "-" { collapsed.removeFirst() }
        while collapsed.last == "-" { collapsed.removeLast() }

        let name = String(collapsed)
        return name.count <= 64 ? name : String(name.prefix(64))
    }

    private func parseComposeResponse(_ content: String) throws -> SkillDraft {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            throw SkillCompositionError.invalidResponse
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let description = parsed["description"] as? String,
              let body = parsed["body"] as? String else {
            throw SkillCompositionError.invalidResponse
        }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty, !trimmedBody.isEmpty else {
            throw SkillCompositionError.invalidResponse
        }
        guard trimmedDescription.count <= 1024 else {
            throw SkillCompositionError.invalidResponse
        }

        return SkillDraft(description: trimmedDescription, body: trimmedBody)
    }

    private func parseResponse(_ content: String, mode: SkillExtractionMode = .automatic) -> SkillExtractionResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            return .skip
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = parsed["action"] as? String else {
            return .skip
        }

        switch action {
        case "new":
            guard let rawName = parsed["name"] as? String,
                  let description = parsed["description"] as? String else {
                return .skip
            }
            let name = Self.normalizeSkillName(rawName)
            guard !name.isEmpty else { return .skip }
            return .newSkill(name: name, description: description)

        case "enhance":
            guard let target = parsed["target"] as? String,
                  let description = parsed["description"] as? String else {
                return .skip
            }
            let normalizedTarget = Self.normalizeSkillName(target)
            guard !normalizedTarget.isEmpty else { return .skip }
            return .enhance(existingName: normalizedTarget, description: description)

        case "skip":
            return .skip

        default:
            // Explicit mode should not invent skip via unknown actions.
            return mode == .explicitRemember ? .skip : .skip
        }
    }
}
