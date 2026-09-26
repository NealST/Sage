//
//  guardian_sender_messages.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/guardian_sender_messages.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct GuardianSenderMessages: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("guardian.sender_messages") }
    public var role: String { "developer" }
    public var openMarker: String { "<guardian_sender_messages>" }
    public var closeMarker: String { "</guardian_sender_messages>" }
    public var body: String { text }
}
