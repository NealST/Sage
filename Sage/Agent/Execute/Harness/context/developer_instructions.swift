//
//  developer_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/developer_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct DeveloperInstructions: ContextualUserFragment, Equatable, Sendable {
    public var instructions: String
    public init(instructions: String) {
        self.instructions = instructions
    }
    public var contentKind: ContentItemKind { ContentItemKind("generic.developer_instructions") }
    public var role: String { "developer" }
    public var openMarker: String { "" }
    public var closeMarker: String { "" }
    public var body: String { instructions }
}
