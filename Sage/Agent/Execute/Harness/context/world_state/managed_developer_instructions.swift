//
//  managed_developer_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/world_state/managed_developer_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct ManagedDeveloperInstructions: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("generic.developer_instructions") }
    public var role: String { "developer" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { text }
}

public struct ManagedDeveloperInstructionsState: Equatable, Sendable {
    public var text: String?

    public init(text: String? = nil) {
        self.text = text
    }

    public func snapshot() -> String? { text }

    public func renderDiff(previous: String?) -> (any ContextualUserFragment)? {
        guard let text, text != previous else { return nil }
        return ManagedDeveloperInstructions(text: text)
    }
}

public func validateManagedDeveloperInstructions(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}
