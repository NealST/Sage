//
//  compact_permissions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/compact_permissions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct CompactPermissionsState: Equatable, Sendable {
    public var summary: String?

    public init(summary: String? = nil) {
        self.summary = summary
    }

    public func snapshot() -> String? { summary }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let summary, summary != previous else { return nil }
        return InternalModelContextFragment(
            source: InternalContextSource.fromStatic("compact_permissions"),
            body: summary
        )
    }
}
