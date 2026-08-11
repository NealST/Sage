//
//  SkillExtractionService.swift
//  Sage
//
//  Analyzes completed tasks to identify reusable experiences worth saving as skills.
//  Uses the cloud model to determine if a task contains valuable patterns, workarounds,
//  or best practices, and generates SKILL.md content accordingly.
//

import Foundation

/// Result of skill extraction analysis.
enum SkillExtractionResult: Sendable {
    /// The task does not contain experience worth saving.
    case skip
    /// A new skill should be created.
    case newSkill(name: String, description: String, body: String)
    /// An existing skill should be enhanced with new knowledge.
    case enhance(existingName: String, description: String, body: String)
}

/// Extracts reusable experiences from completed tasks via cloud model analysis.
actor SkillExtractionService {
    private let modelClient: ModelClient

    init(modelClient: ModelClient = ModelClient()) {
        self.modelClient = modelClient
    }

    /// Analyzes a completed task to determine if it contains reusable experience.
    ///
    /// - Parameters:
    ///   - task: The completed TaskRecord with full event history.
    ///   - existingSkills: Current skill catalog (name, description, and body) for deduplication.
    ///   - settings: Model settings snapshot (captured on MainActor before calling).
    /// - Returns: Extraction result indicating skip, new skill, or enhancement.
    func analyze(
        task: TaskRecord,
        existingSkills: [(name: String, description: String, body: String)],
        settings: ModelSettingsSnapshot
    ) async -> SkillExtractionResult? {

        let transcript = buildTranscript(from: task)
        guard !transcript.isEmpty else { return nil }

        let skillsCatalog = existingSkills.map { skill in
            var entry = "- \(skill.name): \(skill.description)"
            if !skill.body.isEmpty {
                let preview = String(skill.body.prefix(300))
                entry += "\n  Current content: \(preview)\(skill.body.count > 300 ? "…" : "")"
            }
            return entry
        }.joined(separator: "\n")

        let systemPrompt = """
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

        ## Existing Skills
        \(skillsCatalog.isEmpty ? "(none)" : skillsCatalog)

        ## Response Format
        Respond with ONLY a JSON object in one of these formats:

        If not worth saving:
        {"action": "skip", "reason": "brief explanation"}

        If a new skill should be created:
        {"action": "new", "name": "kebab-case-name", "description": "One sentence description", "body": "Full SKILL.md content in markdown"}

        If an existing skill should be enhanced:
        {"action": "enhance", "target": "existing-skill-name", "description": "Updated description", "body": "Complete new SKILL.md content (replaces old version)"}

        ## SKILL.md Format
        The body should follow this structure:
        ```
        ---
        description: One sentence description
        source: auto-generated
        ---

        # Skill Name

        [Main content: the experience, best practice, or workflow in clear actionable form]
        ```

        Output ONLY the JSON object, nothing else.
        """

        let userPrompt = """
        ## Task Summary
        \(task.topic ?? task.summary ?? "Untitled task")

        ## Task Transcript
        \(transcript)
        """

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

            guard let content = turn.content else { return .skip }
            return parseResponse(content)
        } catch {
            return nil
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
        var result = lowered.map { char -> Character in
            if char.isASCII && (char.isLowercase || char.isNumber) { return char }
            if char == "-" || char == "_" || char == " " { return "-" }
            return Character("")
        }.filter { $0 != Character("") }

        // Collapse consecutive hyphens
        var collapsed: [Character] = []
        for char in result {
            if char == "-" && collapsed.last == "-" { continue }
            collapsed.append(char)
        }
        result = collapsed

        // Trim leading/trailing hyphens
        while result.first == "-" { result.removeFirst() }
        while result.last == "-" { result.removeLast() }

        let name = String(result)
        return name.count <= 64 ? name : String(name.prefix(64))
    }

    private func parseResponse(_ content: String) -> SkillExtractionResult {
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
                  let description = parsed["description"] as? String,
                  let body = parsed["body"] as? String else {
                return .skip
            }
            let name = Self.normalizeSkillName(rawName)
            guard !name.isEmpty else { return .skip }
            return .newSkill(name: name, description: description, body: body)

        case "enhance":
            guard let target = parsed["target"] as? String,
                  let description = parsed["description"] as? String,
                  let body = parsed["body"] as? String else {
                return .skip
            }
            // Normalize: trim whitespace, lowercase (skill names are always lowercase kebab-case)
            let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return .enhance(existingName: normalizedTarget, description: description, body: body)

        default:
            return .skip
        }
    }
}
