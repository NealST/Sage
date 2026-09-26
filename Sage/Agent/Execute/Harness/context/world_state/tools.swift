//
//  tools.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/tools.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct ToolsState: Equatable, Sendable {
    public var names: [String]

    public init(names: [String] = []) {
        self.names = names
    }

    public func snapshot() -> String? {
        names.isEmpty ? nil : names.joined(separator: ",")
    }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let snapshot = snapshot(), snapshot != previous else { return nil }
        return InternalModelContextFragment(
            source: InternalContextSource.fromStatic("tools"),
            body: "Available tools: \(snapshot)"
        )
    }
}
