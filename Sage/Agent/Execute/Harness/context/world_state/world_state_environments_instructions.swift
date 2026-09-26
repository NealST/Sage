//
//  world_state_environments_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/environments_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct EnvironmentsInstructionsState: Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func snapshot() -> String? { enabled ? "1" : nil }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard enabled, previous == nil else { return nil }
        return EnvironmentsInstructions()
    }
}
