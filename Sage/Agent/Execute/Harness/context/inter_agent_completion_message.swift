//
//  inter_agent_completion_message.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/inter_agent_completion_message.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct InterAgentCompletionMessage: ContextualUserFragment, Equatable, Sendable {
    public var sender: String
    public var summary: String

    public init(sender: String, summary: String) {
        self.sender = sender
        self.summary = summary
    }

    public var contentKind: ContentItemKind { ContentItemKind("inter_agent.completion") }
    public var role: String { "user" }
    public var openMarker: String { "<inter_agent_completion>" }
    public var closeMarker: String { "</inter_agent_completion>" }
    public var body: String { "Agent \(sender) completed:\n\(summary)" }
}
