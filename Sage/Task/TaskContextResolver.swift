//
//  TaskContextResolver.swift
//  Sage
//

import Foundation

nonisolated enum TaskContextAction: Sendable, Equatable {
    case continueActive
    case beginNew
    case resumeTask(UUID)
}

nonisolated struct TaskContextDecision: Sendable, Equatable {
    var action: TaskContextAction
    var relatedTaskIDs: [UUID]
    var confidence: Double
    var reason: String
    var userVisibleHint: String?

    var eventContext: EventContext {
        EventContext(
            relatedTaskIDs: relatedTaskIDs,
            confidence: confidence,
            reason: reason
        )
    }
}

/// Strategy seam for deterministic rules, an on-device model, or a hybrid resolver.
nonisolated protocol TaskContextResolving: Sendable {
    func resolve(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) async -> TaskContextDecision
}

/// First-pass filter only: explicit fresh-start language, or no active task.
/// Semantic resume / topic-drift is handled by `TaskRouter` (+ heuristic fallback).
nonisolated struct ContinuityTaskResolver: TaskContextResolving {
    func resolve(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) async -> TaskContextDecision {
        if Self.requestsFreshStart(input) {
            return TaskContextDecision(
                action: .beginNew,
                relatedTaskIDs: [],
                confidence: 1,
                reason: "User requested a fresh start",
                userVisibleHint: nil
            )
        }

        guard workspace.activeTaskID != nil else {
            return TaskContextDecision(
                action: .beginNew,
                relatedTaskIDs: [],
                confidence: 1,
                reason: "No active task",
                userVisibleHint: nil
            )
        }

        return TaskContextDecision(
            action: .continueActive,
            relatedTaskIDs: workspace.activeTask?.relatedTaskIDs ?? [],
            confidence: 1,
            reason: "Continuous workspace policy",
            userVisibleHint: nil
        )
    }

    private static func requestsFreshStart(_ input: String) -> Bool {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let phrases = [
            "start fresh",
            "start over",
            "new task",
            "forget previous",
            "forget the previous",
            "don't reference previous",
            "do not reference previous",
            "ignore previous",
            "重新开始",
            "新任务",
            "不要参考之前",
            "忘掉之前",
            "忘记之前",
            "别参考之前",
        ]
        return phrases.contains { normalized.contains($0) }
    }
}

/// Cheap bag-of-words fallback used when the local model is unavailable or
/// returns an unparseable result. Never blocks the user.
nonisolated enum HeuristicTaskFallback {
    /// Returns a non-continue decision when the heuristic is confident enough;
    /// otherwise `nil` (caller should continue the active task).
    static func decide(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) -> TaskContextDecision? {
        let activeID = workspace.activeTaskID
        let active = workspace.activeTask
        let activeIsEmpty = active?.events.isEmpty ?? true

        if activeIsEmpty {
            guard let activeID else { return nil }
            guard let match = bestRelatedSummary(
                input: input,
                summaries: workspace.recentSummaries,
                excluding: activeID
            ) else { return nil }
            return TaskContextDecision(
                action: .resumeTask(match.id),
                relatedTaskIDs: [],
                confidence: match.score,
                reason: "Fallback: matched prior task",
                userVisibleHint: hint(from: match)
            )
        }

        guard let active else { return nil }
        // Conservative topic-drift signal: enough history, an anchor label, and
        // essentially no lexical overlap with the new message.
        let anchor = [active.topic, active.abstract, active.summary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !anchor.isEmpty, active.events.count >= 4 else { return nil }

        let inputTokens = significantTokens(in: input)
        let anchorTokens = significantTokens(in: anchor)
        guard inputTokens.count >= 3, !anchorTokens.isEmpty else { return nil }

        let overlap = inputTokens.intersection(anchorTokens).count
        let score = Double(overlap) / Double(inputTokens.count)
        guard overlap == 0, score < 0.15 else { return nil }

        return TaskContextDecision(
            action: .beginNew,
            relatedTaskIDs: [],
            confidence: 0.55,
            reason: "Fallback: low overlap with current topic",
            userVisibleHint: nil
        )
    }

    private struct RelatedMatch {
        var id: UUID
        var topic: String?
        var summary: String?
        var score: Double
    }

    private static func bestRelatedSummary(
        input: String,
        summaries: [TaskSummary],
        excluding activeID: UUID
    ) -> RelatedMatch? {
        let tokens = significantTokens(in: input)
        guard tokens.count >= 2 else { return nil }

        var best: RelatedMatch?
        for summary in summaries where summary.id != activeID {
            guard summary.status != .awaitingApproval else { continue }
            let haystack = [summary.topic, summary.abstract, summary.summary]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !haystack.isEmpty else { continue }
            let summaryTokens = significantTokens(in: haystack)
            guard !summaryTokens.isEmpty else { continue }
            let overlap = tokens.intersection(summaryTokens).count
            let score = Double(overlap) / Double(tokens.count)
            guard score >= 0.5, overlap >= 2 else { continue }
            if best == nil || score > best!.score {
                best = RelatedMatch(
                    id: summary.id,
                    topic: summary.topic,
                    summary: summary.summary,
                    score: score
                )
            }
        }
        return best
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

    private static func hint(from match: RelatedMatch) -> String {
        if let topic = match.topic?.trimmingCharacters(in: .whitespacesAndNewlines),
           !topic.isEmpty {
            return "Using context from “\(topic)”"
        }
        guard let summary = match.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty
        else {
            return "Using context from a related task"
        }
        let clipped = summary.count > 48
            ? String(summary.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            : summary
        return "Using context from “\(clipped)”"
    }
}

private extension Character {
    /// CJK Unified Ideographs + common extensions used in zh/ja labels.
    nonisolated var isCJKUnified: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF,  // CJK Unified
                 0x3400...0x4DBF,  // Extension A
                 0x3040...0x30FF,  // Hiragana + Katakana
                 0xAC00...0xD7AF:  // Hangul
                return true
            default:
                return false
            }
        }
    }
}
