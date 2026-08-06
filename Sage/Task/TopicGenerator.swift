//
//  TopicGenerator.swift
//  Sage
//
//  Generates and updates task topic/abstract using the local MLX model.
//

import Foundation

/// Result of topic generation.
nonisolated struct TopicResult: Sendable, Equatable {
    var topic: String
    var abstract: String
}

/// Generates concise topic labels and abstracts for tasks.
actor TopicGenerator {
    private let modelService: LocalModelService

    init(modelService: LocalModelService = .shared) {
        self.modelService = modelService
    }

    /// Generates a topic and abstract from the task's key events.
    ///
    /// - Parameter events: The task's event history.
    /// - Returns: A `TopicResult`, or nil if the model is unavailable.
    func generate(from events: [AgentEvent]) async -> TopicResult? {
        guard await modelService.isReady else { return nil }

        let firstUser = events.first(where: { $0.kind == .userInput })?.content
        let lastUser = events.last(where: { $0.kind == .userInput })?.content
        let lastAssistant = events.last(where: {
            $0.kind == .assistantResponse && ($0.toolCalls?.isEmpty ?? true)
        })?.content

        guard let firstUser else { return nil }

        let (system, user) = Self.buildPrompt(
            firstUser: firstUser,
            lastUser: lastUser != firstUser ? lastUser : nil,
            lastAssistant: lastAssistant
        )

        do {
            let output = try await modelService.generate(
                systemPrompt: system,
                userPrompt: user,
                maxTokens: 60,
                temperature: 0
            )
            return Self.parse(output: output)
        } catch {
            return nil
        }
    }

    /// Updates an existing topic when a task is resumed with new content.
    ///
    /// - Parameters:
    ///   - existingTopic: The current topic label.
    ///   - existingAbstract: The current abstract.
    ///   - newInput: The new user input that triggered the resume.
    /// - Returns: Updated `TopicResult`, or nil if no update needed.
    func update(
        existingTopic: String,
        existingAbstract: String,
        newInput: String
    ) async -> TopicResult? {
        guard await modelService.isReady else { return nil }

        let (system, user) = Self.buildUpdatePrompt(
            existingTopic: existingTopic,
            existingAbstract: existingAbstract,
            newInput: newInput
        )

        do {
            let output = try await modelService.generate(
                systemPrompt: system,
                userPrompt: user,
                maxTokens: 60,
                temperature: 0
            )
            return Self.parse(output: output)
        } catch {
            return nil
        }
    }

    // MARK: - Prompts

    private static func buildPrompt(
        firstUser: String,
        lastUser: String?,
        lastAssistant: String?
    ) -> (system: String, user: String) {
        let system = """
        Generate a concise topic label and abstract for a task based on its conversation history.

        Rules:
        - topic: a short label, max 20 characters, in the user's language
        - abstract: one sentence describing the intent, max 80 characters, in the user's language

        Output ONLY this JSON format: {"topic":"...","abstract":"..."}
        """

        var history = "First request: \(String(firstUser.prefix(200)))"
        if let lastUser {
            history += "\nLatest request: \(String(lastUser.prefix(200)))"
        }
        if let lastAssistant {
            history += "\nResult: \(String(lastAssistant.prefix(200)))"
        }

        return (system, history)
    }

    private static func buildUpdatePrompt(
        existingTopic: String,
        existingAbstract: String,
        newInput: String
    ) -> (system: String, user: String) {
        let system = """
        A task is being resumed with new content. Update the topic and abstract to reflect the expanded scope.

        Rules:
        - topic: max 20 characters, in the user's language
        - abstract: max 80 characters, in the user's language
        - Keep the original intent but incorporate the new direction

        Output ONLY this JSON format: {"topic":"...","abstract":"..."}
        """
        let user = """
        Current topic: \(existingTopic)
        Current abstract: \(existingAbstract)
        New input: \(String(newInput.prefix(200)))
        """
        return (system, user)
    }

    // MARK: - Parsing

    private static func parse(output: String) -> TopicResult? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            return nil
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONDecoder().decode(TopicOutput.self, from: data) else {
            return nil
        }

        let topic = String(json.topic.prefix(20))
        let abstract = String(json.abstract.prefix(80))

        guard !topic.isEmpty else { return nil }

        return TopicResult(topic: topic, abstract: abstract)
    }
}

private struct TopicOutput: Decodable {
    let topic: String
    let abstract: String
}
