//
//  event_mapping.swift
//  CodexCore
//
//  Port of codex-rs/core/src/event_mapping.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

public func isContextualUserMessageContent(_ item: ResponseItem) -> Bool {
    isGuardianContextMessage(item)
}

public func isContextualDevMessageContent(_ item: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, _) = item, role == "developer" else {
        return false
    }
    return content.contains(where: isContextualUserFragment)
}

public func hasNonContextualDevMessageContent(_ item: ResponseItem) -> Bool {
    guard case .message(_, let role, let content, _, _) = item, role == "developer" else {
        return false
    }
    return content.contains { !isContextualUserFragment($0) }
}

public func parseTurnItem(_ item: ResponseItem) -> ResponseItem {
    item
}
