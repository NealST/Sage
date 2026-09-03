//
//  TaskContextResolver.swift
//  Sage
//

import Foundation

/// First-pass filter only: no active task, or keep the current one sticky.
/// Fresh-start language becomes a Start Fresh offer — it does not switch.
nonisolated struct ContinuityTaskResolver: TaskRouting {
    func route(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) -> TaskRoute {
        guard workspace.activeTaskID != nil else {
            return .beginNew(reason: "No active task")
        }

        if Self.requestsFreshStart(input) {
            return .continueActive(
                relatedTaskIDs: workspace.activeTask?.relatedTaskIDs ?? [],
                reason: "User asked to start fresh; wait for confirmation",
                shouldOfferFreshStart: true
            )
        }

        return .continueActive(
            relatedTaskIDs: workspace.activeTask?.relatedTaskIDs ?? [],
            reason: "Continuous workspace policy"
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
