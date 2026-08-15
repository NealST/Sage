//
//  TopicGenerator.swift
//  Sage
//
//  Deterministic topic / abstract labels from task text (no on-device model).
//

import Foundation

/// Result of topic generation.
nonisolated struct TopicResult: Sendable, Equatable {
    var topic: String
    var abstract: String
}

/// Generates concise topic labels and abstracts for tasks.
enum TopicGenerator {
    /// Topic and abstract from the first user message.
    static func generate(from events: [AgentEvent]) -> TopicResult? {
        guard let firstUser = events.first(where: { $0.kind == .userInput })?.content else {
            return nil
        }
        return fromUserText(firstUser)
    }

    /// Resume keeps the existing label unless the new input is clearly longer/more specific.
    static func update(
        existingTopic: String,
        existingAbstract: String,
        newInput: String
    ) -> TopicResult? {
        let trimmed = newInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= existingTopic.count { return nil }
        return fromUserText(trimmed) ?? TopicResult(topic: existingTopic, abstract: existingAbstract)
    }

    private static func fromUserText(_ text: String) -> TopicResult? {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }

        let topic = clip(collapsed, maxLength: 20)
        let abstract = clip(collapsed, maxLength: 80)
        guard !topic.isEmpty else { return nil }
        return TopicResult(topic: topic, abstract: abstract)
    }

    private static func clip(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        var clipped = String(text[..<end])
        if let space = clipped.lastIndex(of: " "), space > clipped.startIndex {
            clipped = String(clipped[..<space])
        }
        return clipped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
