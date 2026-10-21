//
//  decision.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/decision.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `nil` means “ask the person”. A missing reviewer is never an implicit allow.
//  Live execute consults this from `ToolBatchExecutor` (not `runTurn`).
//

import Foundation

enum GuardianDecision {
    /// Isolated review. `nil` falls through to the HUD card.
    @MainActor
    static func decide(
        action: ApprovalAction,
        context: ApprovalContext,
        options: GuardianReviewOptions,
        events: [AgentEvent] = []
    ) async -> ReviewDecision? {
        await ReviewRuntime(
            request: ReviewAction.from(action),
            reasons: ApprovalRequestReasons(
                approval: context.approvalReason,
                retry: context.retryReason
            ),
            options: options
        ).decide(events: events)
    }
}
