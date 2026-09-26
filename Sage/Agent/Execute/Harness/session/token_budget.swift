//
//  token_budget.swift
//  Sage
//
//  Port of codex-rs/core/src/session/token_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

func hasExplicitSettings(_ settings: StepSettings) -> Bool {
    settings.reasoningEffort != nil || settings.serviceTier != nil
}

func resolveTokenBudget(modelContextWindow: Int64?, occupancy: Double) -> Int64? {
    guard let modelContextWindow else { return nil }
    return Int64(Double(modelContextWindow) * max(0, 1 - occupancy))
}

extension Session {
    func remainingContextTokens() -> Int64? {
        state.tokenInfo()?.modelContextWindow.map { window in
            max(window - (state.tokenInfo()?.totalTokenUsage.totalTokens ?? 0), 0)
        }
    }
}
