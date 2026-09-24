//
//  feedback.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/feedback.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  A failed review keeps the action text so the next card can show why
//  the isolated reviewer did not finish.
//

import Foundation

struct FailedReviewFeedback: Equatable, Sendable {
    var reviewID: String
    var action: String
    var reason: String
}

enum GuardianFeedback {
    static func record(
        reviewID: String,
        action: String,
        error: Error
    ) -> FailedReviewFeedback {
        FailedReviewFeedback(
            reviewID: reviewID,
            action: action,
            reason: error.localizedDescription
        )
    }
}
