//
//  review_request.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/review_request.rs (Apache-2.0)
//  plus `routes_approval_policy_to_guardian` from
//  codex-rs/ext/guardian-reviewer/src/routing.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Whether an action goes to Guardian before the HUD card.
//

import CodexProtocol
import Foundation

enum GuardianReviewRequest {
    /// Codex `routes_approval_policy_to_guardian`.
    static func routesApprovalPolicyToGuardian(
        policy: CodexProtocol.AskForApproval,
        reviewer: ApprovalsReviewer
    ) -> Bool {
        switch policy {
        case .onRequest, .granular:
            return reviewer == .autoReview
        case .unlessTrusted, .never:
            return false
        }
    }

    static func approvalsReviewer(for policy: PathGuard.Policy) -> ApprovalsReviewer {
        Guardian.strictAutoReviewEnabled(policy: policy) ? .autoReview : .user
    }

    /// Project mode, sandbox escalations, AutoReview-on-request, and a
    /// non-disabled model policy all go through Guardian before the card.
    static func routesToGuardian(
        policy: PathGuard.Policy,
        retry: Bool,
        scope: GuardianScope,
        approvalPolicy: CodexProtocol.AskForApproval = .onRequest,
        reviewer: ApprovalsReviewer? = nil,
        reviewMode: GuardianReviewMode? = nil
    ) -> Bool {
        if retry { return true }
        if reviewMode == .disabled { return false }
        if Guardian.strictAutoReviewEnabled(policy: policy) { return true }
        _ = scope
        return routesApprovalPolicyToGuardian(
            policy: approvalPolicy,
            reviewer: reviewer ?? approvalsReviewer(for: policy)
        )
    }
}
