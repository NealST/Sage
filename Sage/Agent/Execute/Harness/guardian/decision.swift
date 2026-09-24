//
//  decision.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/decision.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  `nil` means “ask the person”. A missing reviewer is never an implicit allow.
//

import Foundation

enum GuardianDecision {
    /// Isolated review. `nil` falls through to the HUD card.
    @MainActor
    static func decide(
        action: ApprovalAction,
        context: ApprovalContext,
        options: GuardianReviewOptions
    ) async -> ReviewDecision? {
        let request = GuardianApprovalRequest.from(action)
        let prepared = PreparedGuardianContext.prepare(
            request: request,
            approvalReason: context.approvalReason,
            retryReason: context.retryReason
        )
        let usable = PromptBudget.forModel(
            ModelSettings.shared.snapshot(for: .review).model
        ).usableTokens
        if GuardianRequestBudget.check(
            prompt: prepared.user,
            instructions: prepared.system,
            usableTokens: usable
        ) != nil {
            return .denied(reason: "Guardian review input exceeds the context window.")
        }
        do {
            let raw = try await GuardianReviewSession.shared.review(prompt: prepared.user)
            if let parsed = GuardianPrompt.parse(raw) {
                return parsed
            }
            if GuardianPrompt.isAsk(raw) {
                return nil
            }
            if options.requireGuardian {
                return .denied(reason: "Guardian could not review this action.")
            }
            return nil
        } catch {
            _ = GuardianFeedback.record(
                reviewID: prepared.reviewID,
                action: request.pretty(),
                error: error
            )
            return nil
        }
    }
}
