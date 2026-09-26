//
//  context_window_guidance.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/context_window_guidance.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct ContextWindowGuidanceState: Equatable, Sendable {
    public var text: String?

    public init(text: String? = nil) {
        self.text = text
    }

    public func snapshot() -> String? { text }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let text, text != previous else { return nil }
        return ContextWindowGuidance(text: text)
    }
}
