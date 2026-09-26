//
//  compact_token_budget.swift
//  CodexCore
//
//  Port of codex-rs/core/src/compact_token_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct CompactTokenBudget: Equatable, Sendable {
    public var usableTokens: Int64
    public var usedTokens: Int64

    public init(usableTokens: Int64, usedTokens: Int64 = 0) {
        self.usableTokens = usableTokens
        self.usedTokens = usedTokens
    }

    public var occupancy: Double {
        guard usableTokens > 0 else { return 1 }
        return min(Double(usedTokens) / Double(usableTokens), 1)
    }

    public var shouldCompact: Bool {
        occupancy >= 0.90
    }
}
