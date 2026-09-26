//
//  hook_additional_context.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/hook_additional_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct HookAdditionalContext: ContextualUserFragment, Equatable, Sendable {
    public var text: String
    public init(text: String) {
        self.text = text
    }
    public var contentKind: ContentItemKind { ContentItemKind("hooks.additional_context") }
    public var role: String { "user" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { text }
}
