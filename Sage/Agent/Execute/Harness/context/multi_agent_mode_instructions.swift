//
//  multi_agent_mode_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/multi_agent_mode_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Phase 9 owns the full multi-agent prompt. This keeps the fragment shape.
//

import CodexProtocol
import Foundation

public struct MultiAgentModeInstructions: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("multi_agent.mode_instructions") }
    public var role: String { "developer" }
    public var openMarker: String { "<multi_agent_mode_instructions>" }
    public var closeMarker: String { "</multi_agent_mode_instructions>" }
    public var body: String { text }
}
