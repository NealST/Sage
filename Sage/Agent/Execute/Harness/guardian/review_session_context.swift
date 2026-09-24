//
//  review_session_context.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/review_session_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  The reviewer sees recent user and tool lines, truncated to the same
//  per-entry cap Codex uses for a synchronous review.
//

import Foundation

enum GuardianReviewSessionContext {
    static let maxToolEntryTokens = 2_000
    static let maxRootMessageTokens = 900

    static func transcript(events: [AgentEvent], limit: Int = 12) -> String {
        let recent = events.suffix(limit)
        return recent.map { event in
            let cap = event.kind == .toolResult ? maxToolEntryTokens : maxRootMessageTokens
            let text = GuardianPrompt.truncate(event.content, tokenCap: cap)
            return "\(event.kind.rawValue): \(text)"
        }.joined(separator: "\n")
    }
}
