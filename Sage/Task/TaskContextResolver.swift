//
//  TaskContextResolver.swift
//  Sage
//

import Foundation

/// First-pass filter only: explicit fresh-start language, or no active task.
/// Otherwise the current task stays sticky — no silent resume or split.
nonisolated struct ContinuityTaskResolver: TaskRouting {
    func route(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) async -> TaskRoute {
        if Self.requestsFreshStart(input) {
            return .beginNew(reason: "User requested a fresh start")
        }

        guard workspace.activeTaskID != nil else {
            return .beginNew(reason: "No active task")
        }

        return .continueActive(
            relatedTaskIDs: workspace.activeTask?.relatedTaskIDs ?? [],
            reason: "Continuous workspace policy"
        )
    }

    /// Legacy name used by older call sites / tests.
    func resolve(
        input: String,
        workspace: TaskWorkspaceSnapshot
    ) async -> TaskRoute {
        await route(input: input, workspace: workspace)
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
