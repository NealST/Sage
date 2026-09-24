//
//  request_budget.swift
//  Sage
//
//  Port of codex-rs/core/src/guardian/request_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Checks the assembled reviewer prompt, including the margin Codex keeps
//  so a continuation cannot overflow the window.
//

import Foundation

enum ExhaustedReviewBudget: Equatable {
    case detected
    case compacting
}

enum GuardianRequestBudget {
    static let inputTokenMargin = 256

    static func estimateTokens(prompt: String, instructions: String) -> Int {
        PromptBudget.estimatedTokenCount(in: prompt) + PromptBudget.estimatedTokenCount(in: instructions)
    }

    static func check(prompt: String, instructions: String, usableTokens: Int) -> ExhaustedReviewBudget? {
        let total = estimateTokens(prompt: prompt, instructions: instructions)
        let limit = max(usableTokens - inputTokenMargin, 1)
        if total > limit {
            return .detected
        }
        return nil
    }
}
