//
//  realtime.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/realtime.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Realtime voice fragments stay Phase 10. This only tracks the flag.
//

import Foundation

public struct RealtimeState: Equatable, Sendable {
    public var active: Bool

    public init(active: Bool = false) {
        self.active = active
    }

    public func snapshot() -> String? { active ? "1" : nil }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        nil
    }
}
