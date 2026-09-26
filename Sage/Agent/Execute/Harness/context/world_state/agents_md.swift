//
//  agents_md.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/agents_md.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct AgentsMdState: Equatable, Sendable {
    public var directory: String?
    public var text: String?

    public init(directory: String? = nil, text: String? = nil) {
        self.directory = directory
        self.text = text
    }

    public func snapshot() -> String? {
        guard let text else { return nil }
        return "\(directory ?? "")\n\(text)"
    }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let text, snapshot() != previous else { return nil }
        return UserInstructions(directory: directory, text: text)
    }
}
