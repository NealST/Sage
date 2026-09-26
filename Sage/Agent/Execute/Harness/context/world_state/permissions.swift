//
//  permissions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/permissions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct PermissionsState: Equatable, Sendable {
    public var rendered: String?

    public init(rendered: String? = nil) {
        self.rendered = rendered
    }

    public func snapshot() -> String? { rendered }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let rendered, rendered != previous else { return nil }
        return InternalModelContextFragment(
            source: InternalContextSource.fromStatic("permissions"),
            body: rendered
        )
    }
}
