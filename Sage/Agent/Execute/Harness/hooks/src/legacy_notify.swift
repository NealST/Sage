//
//  legacy_notify.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/legacy_notify.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `legacy_notify_json` is faithful. Process spawn for `notify_hook` waits
//  on a command runner; the hook reports success when argv is empty.
//

import CodexProtocol
import Foundation

struct UserNotification: Equatable, Sendable, Codable {
    var type_: String
    var threadId: String
    var turnId: String
    var cwd: String
    var client: String?
    var inputMessages: [String]
    var lastAssistantMessage: String?

    enum CodingKeys: String, CodingKey {
        case type_ = "type"
        case threadId = "thread-id"
        case turnId = "turn-id"
        case cwd
        case client
        case inputMessages = "input-messages"
        case lastAssistantMessage = "last-assistant-message"
    }
}

public func legacyNotifyJSON(_ payload: HookPayload) throws -> String {
    switch payload.hookEvent {
    case .afterAgent(let event):
        let notification = UserNotification(
            type_: "agent-turn-complete",
            threadId: event.threadId.description,
            turnId: event.turnId,
            cwd: payload.cwd.display,
            client: payload.client,
            inputMessages: event.inputMessages,
            lastAssistantMessage: event.lastAssistantMessage
        )
        let data = try JSONEncoder().encode(notification)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CodexErr.invalidRequest("legacy_notify_json produced non-UTF8 JSON")
        }
        return json
    }
}

public func notifyHook(argv: [String]) -> Hook {
    Hook(name: "legacy_notify") { payload in
        if argv.isEmpty || argv[0].isEmpty {
            return .success
        }
        do {
            _ = try legacyNotifyJSON(payload)
            return .success
        } catch {
            return .failedContinue(error)
        }
    }
}
