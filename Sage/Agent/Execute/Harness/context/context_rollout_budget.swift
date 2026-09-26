//
//  context_rollout_budget.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/rollout_budget.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  R4a: basename `rollout_budget.swift` collides with core/src/rollout_budget.rs.
//

import CodexProtocol
import Foundation

public struct RolloutBudgetContext: ContextualUserFragment, Equatable, Sendable {
    public var remainingTokens: Int64
    public init(remainingTokens: Int64) {
        self.remainingTokens = remainingTokens
    }
    public var contentKind: ContentItemKind { ContentItemKind("rollout_budget.remaining_tokens") }
    public var role: String { "developer" }
    public var openMarker: String { "<rollout_budget>\n" }
    public var closeMarker: String { "\n</rollout_budget>" }
    public var body: String { "You have \(remainingTokens) weighted tokens left in the shared session token budget." }
}
