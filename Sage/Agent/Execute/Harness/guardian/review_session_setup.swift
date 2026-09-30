//
//  review_session_setup.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/review_session_setup.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Assembles the isolated reviewer prompt from `GuardianReviewerConfig`.
//  Session spawn / prewarm stay out.
//

import Foundation

struct PreparedGuardianContext: Sendable {
    var reviewID: String
    var system: String
    var user: String
    var scope: GuardianScope

    static func prepare(
        request: GuardianApprovalRequest,
        approvalReason: String?,
        retryReason: String?,
        events: [AgentEvent] = [],
        config: GuardianReviewerConfig? = nil
    ) -> PreparedGuardianContext {
        PreparedGuardianContext(
            reviewID: Guardian.newReviewID(),
            system: config?.instructions ?? GuardianPrompt.system,
            user: GuardianPrompt.user(
                request: request,
                approvalReason: approvalReason,
                retryReason: retryReason,
                transcript: GuardianReviewSessionContext.transcript(events: events)
            ),
            scope: request.scope
        )
    }
}
