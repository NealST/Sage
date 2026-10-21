//
//  token_budget_startup.swift
//  Sage
//
//  Port of codex-rs/core/src/config/token_budget_startup.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

struct TokenBudgetStartup: Equatable, Sendable {
    var modelContextWindow: Int64?

    init(modelContextWindow: Int64? = nil) {
        self.modelContextWindow = modelContextWindow
    }
}
