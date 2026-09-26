//
//  plugin_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/plugin_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct PluginInstructions: ContextualUserFragment, Equatable, Sendable {
    public var text: String
    public init(text: String) {
        self.text = text
    }
    public var contentKind: ContentItemKind { ContentItemKind("plugins.instructions") }
    public var role: String { "developer" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { text }
}
