//
//  sender_context.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/sender_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Host-delivered sender provenance waits on retained history / ThreadManager.
//

import CodexProtocol
import Foundation

extension LocalAgentRuntime {
    public func captureSenderUserMessages(
        item: ResponseItem,
        receiverThreadId: ThreadId,
        receiverTurnId: String
    ) async -> Bool {
        false
    }
}
