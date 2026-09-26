//
//  multi_agent_usage_hint.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/multi_agent_usage_hint.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct MultiAgentUsageHint: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("multi_agent.usage_hint") }
    public var role: String { "developer" }
    public var openMarker: String { "<multi_agent_usage_hint>" }
    public var closeMarker: String { "</multi_agent_usage_hint>" }
    public var body: String { text }
}
