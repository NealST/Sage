//
//  subagent_notification.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/subagent_notification.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct SubagentNotification: ContextualUserFragment, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("subagent.notification") }
    public var role: String { "user" }
    public var openMarker: String { "<subagent_notification>" }
    public var closeMarker: String { "</subagent_notification>" }
    public var body: String { text }
}
