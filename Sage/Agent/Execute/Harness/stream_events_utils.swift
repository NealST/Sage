//
//  stream_events_utils.swift
//  CodexCore
//
//  Port of codex-rs/core/src/stream_events_utils.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  ResponseEvent parsing waits for Phase 6 ModelClient. This keeps
//  assistant-message extraction used by compact/session.
//

import CodexProtocol
import Foundation

public func getLastAssistantMessage(from items: [ResponseItem]) -> String? {
    for item in items.reversed() {
        if case .message(_, let role, let content, _, _) = item, role == "assistant" {
            let text = content.compactMap { part -> String? in
                if case .outputText(let text) = part { return text }
                if case .inputText(let text) = part { return text }
                return nil
            }.joined()
            if !text.isEmpty { return text }
        }
    }
    return nil
}
