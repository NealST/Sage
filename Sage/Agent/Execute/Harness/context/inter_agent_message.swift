//
//  inter_agent_message.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/inter_agent_message.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public enum InterAgentMessageType: String, Equatable, Sendable {
    case user
    case assistant
    case system
}

public struct InterAgentMessage: ContextualUserFragment, Equatable, Sendable {
    public var messageType: InterAgentMessageType
    public var sender: String
    public var text: String

    public init(messageType: InterAgentMessageType, sender: String, text: String) {
        self.messageType = messageType
        self.sender = sender
        self.text = text
    }

    public var contentKind: ContentItemKind { ContentItemKind("inter_agent.message") }
    public var role: String { "user" }
    public var openMarker: String { "<inter_agent_message>" }
    public var closeMarker: String { "</inter_agent_message>" }
    public var body: String {
        "From \(sender) (\(messageType.rawValue)):\n\(text)"
    }
}
