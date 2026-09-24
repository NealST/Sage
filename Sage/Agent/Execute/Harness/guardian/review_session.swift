//
//  review_session.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/review_session.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  One isolated completion. Tests can replace `complete`.
//

import Foundation

@MainActor
final class GuardianReviewSession {
    static let shared = GuardianReviewSession()

    /// Test seam. Production talks to the review-role model.
    var complete: ((String) async throws -> String)?

    func review(prompt: String) async throws -> String {
        if let complete {
            return try await complete(prompt)
        }
        let settings = ModelSettings.shared.snapshot(for: .review)
        guard !settings.apiKey.isEmpty else {
            throw GuardianReviewError.notConfigured
        }
        let turn = try await ModelClient().complete(
            events: [
                AgentEvent(kind: .systemInstruction, content: GuardianPrompt.system),
                AgentEvent(kind: .userInput, content: prompt),
            ],
            tools: [],
            settings: settings,
            toolChoice: "none",
            temperature: 0
        )
        return turn.content ?? ""
    }
}

enum GuardianReviewError: Error {
    case notConfigured
}
