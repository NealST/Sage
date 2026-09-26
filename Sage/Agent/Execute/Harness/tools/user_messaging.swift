//
//  user_messaging.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/user_messaging.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Guardian truncation waits for Phase 8. Successful user-messaging MCP
//  payloads still extract the `text` field.
//

import CodexProtocol
import Foundation

let USER_MESSAGING_TOOL_NAMES: Set<String> = [
    "mcp__codex_apps__user_messaging__send_message",
    "mcp__codex_apps__user_messaging_send_message",
    "mcp__codex_apps__user_message__send_message",
    "mcp__codex_apps__user_message_send_message",
]

extension AnyToolResult {
    func deliveredAssistantMessage() -> String? {
        guard result.successForLogging() else { return nil }
        guard let payload = postToolUsePayload else { return nil }
        guard USER_MESSAGING_TOOL_NAMES.contains(payload.toolName.name()) else { return nil }
        guard let object = payload.toolInput.objectValue,
              let text = object["text"]?.stringValue else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
