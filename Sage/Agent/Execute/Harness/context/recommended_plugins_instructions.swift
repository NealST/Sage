//
//  recommended_plugins_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/recommended_plugins_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct RecommendedPluginsInstructions: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("plugins.recommended") }
    public var role: String { "user" }
    public var openMarker: String { "<recommended_plugins>" }
    public var closeMarker: String { "</recommended_plugins>" }
    public var body: String { text }
}
