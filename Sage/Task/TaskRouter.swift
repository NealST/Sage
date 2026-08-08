//
//  TaskRouter.swift
//  Sage
//
//  Uses the local MLX model to route user input to the correct task:
//  continue the current task, resume a related prior task, or start fresh.
//

import Foundation

/// The routing decision produced by the local model.
nonisolated struct TaskRoutingDecision: Sendable, Equatable {
    enum Action: Sendable, Equatable {
        case continueActive
        case resumeTask(UUID)
        case beginNew
    }

    var action: Action
    var confidence: Double
    var reason: String
}

/// Builds the task catalog string for the routing prompt.
nonisolated struct TaskCatalog: Sendable {
    let entries: [Entry]

    struct Entry: Sendable {
        let id: UUID
        let topic: String
        let abstract: String
    }

    /// Builds a catalog from recent summaries, excluding the active task.
    static func build(
        from summaries: [TaskSummary],
        excluding activeID: UUID?
    ) -> TaskCatalog {
        let entries = summaries.compactMap { summary -> Entry? in
            guard summary.id != activeID else { return nil }
            guard summary.status != .awaitingApproval else { return nil }
            guard let topic = summary.topic, !topic.isEmpty else { return nil }
            let abstract = summary.abstract ?? summary.summary ?? ""
            return Entry(id: summary.id, topic: topic, abstract: abstract)
        }
        return TaskCatalog(entries: Array(entries.prefix(15)))
    }

    /// Formats the catalog for the prompt.
    var promptText: String {
        if entries.isEmpty { return "(empty)" }
        return entries.enumerated().map { index, entry in
            "\(index + 1). [\(entry.id.uuidString.prefix(8))] \(entry.topic): \(entry.abstract)"
        }.joined(separator: "\n")
    }

    /// Resolves a short ID prefix from model output to a full UUID.
    func resolve(idPrefix: String) -> UUID? {
        let cleaned = idPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return entries.first {
            $0.id.uuidString.lowercased().hasPrefix(cleaned.lowercased())
        }?.id
    }
}

/// Routes user input using the local MLX model.
actor TaskRouter {
    private let modelService: LocalModelService

    init(modelService: LocalModelService = .shared) {
        self.modelService = modelService
    }

    /// Determines where the user's input should go.
    ///
    /// Falls back to `continueActive` if the model is unavailable or output
    /// cannot be parsed — never blocks the user from working.
    func route(
        input: String,
        currentTopic: String?,
        catalog: TaskCatalog
    ) async -> TaskRoutingDecision {
        guard await modelService.isReady else {
            return .fallbackContinue
        }

        let (system, user) = Self.buildPrompt(
            input: input,
            currentTopic: currentTopic,
            catalog: catalog
        )

        do {
            let output = try await modelService.generate(
                systemPrompt: system,
                userPrompt: user,
                maxTokens: 48,
                temperature: 0
            )
            return Self.parse(output: output, catalog: catalog)
        } catch {
            return .fallbackContinue
        }
    }

    // MARK: - Prompt

    private static func buildPrompt(
        input: String,
        currentTopic: String?,
        catalog: TaskCatalog
    ) -> (system: String, user: String) {
        let currentDesc = currentTopic ?? "(no active topic)"
        let system = """
        You are a task router. Given the user's new message, the current task topic, and a catalog of prior tasks, decide the routing action.

        Rules:
        - If the message continues the current topic, output: {"action":"continue"}
        - If the message relates to a prior task in the catalog, output: {"action":"resume","id":"<8-char-prefix>"}
        - If the message is a new unrelated topic, output: {"action":"new"}

        Output ONLY the JSON object, nothing else.
        """
        let user = """
        Current topic: \(currentDesc)

        Task catalog:
        \(catalog.promptText)

        New message: \(String(input.prefix(300)))
        """
        return (system, user)
    }

    // MARK: - Parsing

    private static func parse(
        output: String,
        catalog: TaskCatalog
    ) -> TaskRoutingDecision {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON from the output
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            return .fallbackContinue
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONDecoder().decode(RouterOutput.self, from: data) else {
            return .fallbackContinue
        }

        switch json.action {
        case "continue":
            return TaskRoutingDecision(
                action: .continueActive,
                confidence: 0.9,
                reason: "Model: continue current topic"
            )
        case "resume":
            guard let idPrefix = json.id,
                  let resolvedID = catalog.resolve(idPrefix: idPrefix) else {
                return .fallbackContinue
            }
            return TaskRoutingDecision(
                action: .resumeTask(resolvedID),
                confidence: 0.85,
                reason: "Model: resume prior task"
            )
        case "new":
            return TaskRoutingDecision(
                action: .beginNew,
                confidence: 0.9,
                reason: "Model: new unrelated topic"
            )
        default:
            return .fallbackContinue
        }
    }
}

// MARK: - Supporting Types

private nonisolated struct RouterOutput: Decodable {
    let action: String
    let id: String?
}

extension TaskRoutingDecision {
    nonisolated static let fallbackContinue = TaskRoutingDecision(
        action: .continueActive,
        confidence: 0.5,
        reason: "Fallback: model unavailable or unparseable"
    )
}
