//
//  guardian_tool_descriptions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/guardian_tool_descriptions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct GuardianToolDescriptions: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("guardian.tool_descriptions") }
    public var role: String { "developer" }
    public var openMarker: String { "<guardian_tool_descriptions>" }
    public var closeMarker: String { "</guardian_tool_descriptions>" }
    public var body: String { text }
}
