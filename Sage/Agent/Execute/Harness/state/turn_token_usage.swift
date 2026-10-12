//
//  turn_token_usage.swift
//  Sage
//
//  Port of codex-rs/core/src/state/turn_token_usage.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  OTel histogram emission is a no-op until the analytics crate is ported.
//

import SageProtocol
import Foundation

struct TurnTokenUsage: Sendable {
    var byModel: [String: SageProtocol.TokenUsage] = [:]

    init() {}

    mutating func record(model: String, usage: SageProtocol.TokenUsage) {
        var total = byModel[model] ?? SageProtocol.TokenUsage()
        total.addAssign(usage)
        byModel[model] = total
    }
}
