//
//  input_budget.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/input_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Rejects a pending review input that cannot fit even without history.
//

import Foundation

enum GuardianInputBudget {
    static let inputTokenMargin = 1_024

    static func checkPending(events: [AgentEvent], usableTokens: Int) -> String? {
        guard let last = events.last(where: { $0.kind == .userInput }) else { return nil }
        let tokens = PromptBudget.estimatedTokenCount(of: last)
        let maximum = max(usableTokens - inputTokenMargin, 1)
        if tokens > maximum {
            return "Guardian review input exceeds the context window."
        }
        return nil
    }
}
