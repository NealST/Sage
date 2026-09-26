//
//  plugins_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/plugins_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct PluginsInstructionsState: Equatable, Sendable {
    public var enabled: Bool
    public var text: String?

    public init(enabled: Bool = false, text: String? = nil) {
        self.enabled = enabled
        self.text = text
    }

    public func snapshot() -> String? {
        guard enabled else { return nil }
        return text ?? "1"
    }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard enabled, previous == nil else { return nil }
        if let text {
            return PluginInstructions(text: text)
        }
        return AvailablePluginsInstructions()
    }
}
