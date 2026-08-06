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

/// Continuity by default; honors explicit fresh-start language; resumes a clearly
/// related prior task when the active workspace is empty.
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

        guard let activeID = workspace.activeTaskID else {
            return TaskContextDecision(
                action: .beginNew,
                relatedTaskIDs: [],
                confidence: 1,
                reason: "No active task",
                userVisibleHint: nil
            )
        }

        let activeIsEmpty = workspace.activeTask?.events.isEmpty ?? true
        if activeIsEmpty,
           let match = Self.bestRelatedSummary(
            input: input,
            summaries: workspace.recentSummaries,
            excluding: activeID
           ) {
            let hint = Self.hint(from: match.summary)
            return TaskContextDecision(
                action: .resumeTask(match.id),
                relatedTaskIDs: [],
                confidence: match.score,
                reason: "Matched prior task summary",
                userVisibleHint: hint
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

    private struct RelatedMatch {
        var id: UUID
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
            // Don't auto-resume a task that still has a pending plan.
            guard summary.status != .awaitingApproval else { continue }
            guard let text = summary.summary, !text.isEmpty else { continue }
            let summaryTokens = significantTokens(in: text)
            guard !summaryTokens.isEmpty else { continue }
            let overlap = tokens.intersection(summaryTokens).count
            let score = Double(overlap) / Double(tokens.count)
            guard score >= 0.5, overlap >= 2 else { continue }
            if best == nil || score > best!.score {
                best = RelatedMatch(id: summary.id, summary: text, score: score)
            }
        }
        return best
    }

    private static func significantTokens(in text: String) -> Set<String> {
        let stop: Set<String> = [
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "my",
            "me", "please", "with", "from", "this", "that", "it", "is", "are",
            "的", "了", "和", "在", "我", "一下", "帮我", "请",
        ]
        return Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count >= 2 && !stop.contains($0) }
        )
    }

    private static func hint(from summary: String?) -> String {
        guard let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
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
