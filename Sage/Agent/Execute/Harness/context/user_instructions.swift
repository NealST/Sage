//
//  user_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/user_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct UserInstructions: ContextualUserFragment, Equatable, Sendable {
    public var directory: String?
    public var text: String
    public init(directory: String?, text: String) {
        self.directory = directory
        self.text = text
    }
    public var contentKind: ContentItemKind { ContentItemKind("agents_md.instructions") }
    public var role: String { "user" }
    public var openMarker: String { "# AGENTS.md instructions" }
    public var closeMarker: String { "</INSTRUCTIONS>" }
    public var body: String { "\(directory.map { " for \($0)" } ?? "")\n\n<INSTRUCTIONS>\n\(text)\n" }
}
