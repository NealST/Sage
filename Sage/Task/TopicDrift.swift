//
//  TopicDrift.swift
//  Sage
//
//  Conservative, non-routing signal that the latest input may belong
//  in a new task. Never splits or resumes on its own.
//

import Foundation

/// Soft offer to start a new task. Confirmation peels the triggering turn
/// off the current thread — it does not happen automatically.
nonisolated struct TopicDriftOffer: Equatable, Sendable {
    let taskID: UUID
    let triggeringUserEventID: UUID
    let topicLabel: String

    var message: String {
        "This doesn’t look like \u{201C}\(topicLabel)\u{201D}."
    }
}

/// Bag-of-words topic-drift detector. Prefer false negatives over nagging.
nonisolated enum TopicDriftDetector {
    /// Short follow-ups (“再试一次”) must not trigger an offer.
    static let minimumInputCharacters = 16
    static let minimumTokenCount = 4
    static let minimumPriorEvents = 4

    static func offer(
        input: String,
        workspace: TaskWorkspaceSnapshot,
        triggeringUserEventID: UUID,
        suppressedTaskID: UUID?
    ) -> TopicDriftOffer? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumInputCharacters else { return nil }

        guard let active = workspace.activeTask else { return nil }
        if let suppressedTaskID, suppressedTaskID == active.id { return nil }
        guard active.events.count >= minimumPriorEvents else { return nil }

        let label = threadLabel(topic: active.topic, abstract: active.abstract, summary: active.summary)
        guard let label else { return nil }

        let anchor = [
            active.topic,
            active.abstract,
            active.summary,
            recentDialogueAnchor(in: active.events),
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !anchor.isEmpty else { return nil }

        let inputTokens = significantTokens(in: trimmed)
        let anchorTokens = significantTokens(in: anchor)
        guard inputTokens.count >= minimumTokenCount, !anchorTokens.isEmpty else { return nil }

        let overlap = inputTokens.intersection(anchorTokens).count
        guard overlap == 0 else { return nil }

        return TopicDriftOffer(
            taskID: active.id,
            triggeringUserEventID: triggeringUserEventID,
            topicLabel: label
        )
    }

    static func threadLabel(topic: String?, abstract: String?, summary: String?) -> String? {
        if let topic = topic?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty {
            return topic
        }
        if let abstract = abstract?.trimmingCharacters(in: .whitespacesAndNewlines), !abstract.isEmpty {
            return clip(abstract, maxLength: 24)
        }
        if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return clip(summary, maxLength: 24)
        }
        return nil
    }

    /// Last plain user/assistant turns — follow-ups often match these, not the title.
    private static func recentDialogueAnchor(in events: [AgentEvent]) -> String? {
        let snippets = events.suffix(6).compactMap { event -> String? in
            switch event.kind {
            case .userInput:
                return event.content
            case .assistantResponse where event.toolCalls?.isEmpty ?? true:
                return event.content
            default:
                return nil
            }
        }
        let joined = snippets.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// Tokenizes Latin words and CJK character bigrams so Chinese input can match.
    static func significantTokens(in text: String) -> Set<String> {
        let stop: Set<String> = [
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "my",
            "me", "please", "with", "from", "this", "that", "it", "is", "are",
            "的", "了", "和", "在", "我", "一下", "帮我", "请", "把", "个", "是",
        ]
        var tokens = Set<String>()
        let segments = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        for segment in segments {
            guard !segment.isEmpty, !stop.contains(segment) else { continue }
            if segment.contains(where: { $0.isCJKUnified }) {
                let chars = Array(segment).filter { $0.isCJKUnified || $0.isNumber }
                guard !chars.isEmpty else { continue }
                if chars.count == 1 {
                    tokens.insert(String(chars[0]))
                    continue
                }
                for index in 0..<(chars.count - 1) {
                    let bigram = String(chars[index...index + 1])
                    if !stop.contains(bigram) {
                        tokens.insert(bigram)
                    }
                }
            } else if segment.count >= 2 {
                tokens.insert(segment)
            }
        }
        return tokens
    }

    private static func clip(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        var clipped = String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if clipped.count == maxLength {
            clipped += "…"
        }
        return clipped
    }
}

private extension Character {
    nonisolated var isCJKUnified: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF,
                 0x3400...0x4DBF,
                 0x3040...0x30FF,
                 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }
}
