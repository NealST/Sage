//
//  guardian_review.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian_review.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Context adapter types used by the host-installed synchronous Guardian
//  extension. `GuardianReviewSession` and `PreparedGuardianContext` already
//  live under `guardian/`. `GuardianReviewState` and `prepare_review_prewarm`
//  wait on Session / TurnContext / ThreadManager.
//

import CodexProtocol
import Foundation

/// Opaque conversation progress retained while ThreadManager starts a reviewer.
struct GuardianReviewState: Sendable {}

func prepareReviewPrewarm() async throws -> PreparedGuardianContext {
    throw CodexErr.unsupportedOperation(
        "prepare_review_prewarm waits on CodexThread / Session / TurnContext"
    )
}
