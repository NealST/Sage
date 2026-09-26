//
//  agent_message_board_notification.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/agent_message_board_notification.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public struct AgentMessageBoardPostPreview: Equatable, Sendable {
    public var author: String
    public var channelName: String
    public var messageId: String
    public var threadId: String
    public var textPreview: String
    public var truncated: Bool

    public init(
        author: String,
        channelName: String,
        messageId: String,
        threadId: String,
        textPreview: String,
        truncated: Bool = false
    ) {
        self.author = author
        self.channelName = channelName
        self.messageId = messageId
        self.threadId = threadId
        self.textPreview = textPreview
        self.truncated = truncated
    }
}

public struct AgentMessageBoardNotification: ContextualUserFragment, Equatable, Sendable {
    public var post: AgentMessageBoardPostPreview

    public init(_ post: AgentMessageBoardPostPreview) {
        self.post = post
    }

    public var contentKind: ContentItemKind { ContentItemKind("agent_message_board.notification") }
    public var role: String { "assistant" }
    public var openMarker: String { "<agent_message_board_notification>" }
    public var closeMarker: String { "</agent_message_board_notification>" }
    public var body: String {
        let suffix = post.truncated ? "\n[Use read_post for the rest.]" : ""
        return """
        Message Type: CHANNEL_POST
        Sender: \(post.author)
        Channel: \(post.channelName)
        Message ID: \(post.messageId)
        Thread ID: \(post.threadId)
        Payload:
        \(post.textPreview)\(suffix)
        """
    }
}
