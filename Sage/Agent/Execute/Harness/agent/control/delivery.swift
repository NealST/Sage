//
//  delivery.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/delivery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

extension AgentMessage {
    public func intoCommunication(
        author: AgentPath,
        recipient: AgentPath,
        mode: MessageDeliveryMode
    ) -> InterAgentCommunication {
        let triggerTurn = mode == .triggerTurn
        switch self {
        case .encrypted(let message):
            return InterAgentCommunication.newEncrypted(
                author: author,
                recipient: recipient,
                otherRecipients: [],
                encryptedContent: message,
                triggerTurn: triggerTurn
            )
        case .plaintext(let message):
            let messageType: InterAgentMessageType = {
                switch mode {
                case .queueOnly: return .message
                case .triggerTurn: return .newTask
                }
            }()
            let content = InterAgentMessage(
                messageType: messageType,
                taskName: recipient,
                sender: author,
                payload: message
            ).renderedText()
            return InterAgentCommunication(
                author: author,
                recipient: recipient,
                otherRecipients: [],
                content: content,
                triggerTurn: triggerTurn
            )
        }
    }
}
