//
//  review.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/review.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Isolated reviewer. Execute still asks the model; this pass only
//  allows, denies, or hands the action back to the user card.
//

import Foundation

enum Guardian {
    static let reviewerName = "guardian"

    static func newReviewID() -> String {
        UUID().uuidString
    }

    /// Codex `strict_auto_review`. Project mode cannot drop Seatbelt quietly.
    static func strictAutoReviewEnabled(policy: PathGuard.Policy) -> Bool {
        if case .project = policy { return true }
        return false
    }

    static func requiresReview(policy: PathGuard.Policy, retry: Bool) -> Bool {
        retry || strictAutoReviewEnabled(policy: policy)
    }
}

struct GuardianReviewOptions: Sendable {
    var requireGuardian = false
    var requireSynchronousReview = true
}
