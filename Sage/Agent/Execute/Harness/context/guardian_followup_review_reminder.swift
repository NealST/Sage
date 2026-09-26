//
//  guardian_followup_review_reminder.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/guardian_followup_review_reminder.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct GuardianFollowupReviewReminder: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("guardian.followup_review_reminder") }
    public var role: String { "developer" }
    public var openMarker: String { "<guardian_followup_review_reminder>" }
    public var closeMarker: String { "</guardian_followup_review_reminder>" }
    public var body: String {
        "A follow-up Guardian review is still pending for this thread."
    }
}
