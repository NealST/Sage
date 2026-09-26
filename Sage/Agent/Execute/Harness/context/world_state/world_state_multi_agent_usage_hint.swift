//
//  world_state_multi_agent_usage_hint.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/multi_agent_usage_hint.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct MultiAgentUsageHintState: Equatable, Sendable {
    public var text: String?

    public init(text: String? = nil) {
        self.text = text
    }

    public func snapshot() -> String? { text }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let text, previous == nil else { return nil }
        return MultiAgentUsageHint(text: text)
    }
}
