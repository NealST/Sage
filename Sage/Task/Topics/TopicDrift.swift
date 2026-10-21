//
//  TopicDrift.swift
//  Sage
//
//  Soft offer + thread title helpers. Plan (`WorkPlan.threadAdvice`) and
//  explicit start-fresh language both surface this chip; neither switches
//  the task until the user confirms Start Fresh.
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

/// Title helpers for chrome / Recents / drift copy. Not a router.
nonisolated enum TopicDriftDetector {
    /// Plan offers stay off until the thread has at least one full exchange.
    static let minimumPriorEvents = 4

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
