//
//  review_request.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/review_request.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Routing half only: whether an action goes to Guardian before the card.
//

import Foundation

enum GuardianReviewRequest {
    /// Project mode and sandbox escalations go through Guardian before the card.
    static func routesToGuardian(policy: PathGuard.Policy, retry: Bool, scope: GuardianScope) -> Bool {
        if Guardian.strictAutoReviewEnabled(policy: policy) { return true }
        if retry { return true }
        switch scope {
        case .shell, .fileChanges, .network, .permissions:
            return false
        case .mcp:
            return false
        }
    }
}
