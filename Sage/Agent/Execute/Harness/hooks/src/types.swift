//
//  types.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/types.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `HookFn` is an async closure. `DateTime<Utc>` is `Date` encoded as
//  RFC3339 seconds with a `Z` suffix. `Box<dyn Error>` is `any Error`.
//

import CodexProtocol
import CodexUtils
import Foundation

public typealias HookFn = @Sendable (HookPayload) async -> HookResult

public enum HookResult: Sendable {
    /// Success: hook completed successfully.
    case success
    /// FailedContinue: hook failed, but other subsequent hooks should still execute and the
    /// operation should continue.
    case failedContinue(any Error)
    /// FailedAbort: hook failed, other subsequent hooks should not execute, and the operation
    /// should be aborted.
    case failedAbort(any Error)

    public var shouldAbortOperation: Bool {
        if case .failedAbort = self { return true }
        return false
    }
}

public struct HookResponse: Sendable {
    public var hookName: String
    public var result: HookResult

    public init(hookName: String, result: HookResult) {
        self.hookName = hookName
        self.result = result
    }
}

public struct Hook: Sendable {
    public var name: String
    public var function: HookFn

    public init(name: String, function: @escaping HookFn) {
        self.name = name
        self.function = function
    }

    public static func `default`() -> Hook {
        Hook(name: "default") { _ in .success }
    }

    public func execute(_ payload: HookPayload) async -> HookResponse {
        HookResponse(hookName: name, result: await function(payload))
    }
}

public struct HookPayload: Equatable, Sendable {
    public var sessionId: ThreadId
    public var cwd: AbsolutePathBuf
    public var client: String?
    public var triggeredAt: Date
    public var hookEvent: HookPayloadEvent

    public init(
        sessionId: ThreadId,
        cwd: AbsolutePathBuf,
        client: String? = nil,
        triggeredAt: Date,
        hookEvent: HookPayloadEvent
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.client = client
        self.triggeredAt = triggeredAt
        self.hookEvent = hookEvent
    }
}

public struct HookEventAfterAgent: Equatable, Sendable {
    public var threadId: ThreadId
    public var turnId: String
    public var inputMessages: [String]
    public var lastAssistantMessage: String?

    public init(
        threadId: ThreadId,
        turnId: String,
        inputMessages: [String],
        lastAssistantMessage: String? = nil
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.inputMessages = inputMessages
        self.lastAssistantMessage = lastAssistantMessage
    }
}

/// Wire tag `event_type` / `after_agent`. Named `HookPayloadEvent` so it does
/// not collide with Sage's existing `HookEvent` turn-runtime enum.
public enum HookPayloadEvent: Equatable, Sendable {
    case afterAgent(HookEventAfterAgent)
}

extension HookPayload: Codable {
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case client
        case triggeredAt = "triggered_at"
        case hookEvent = "hook_event"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(client, forKey: .client)
        try container.encode(rfc3339SecondsZ(triggeredAt), forKey: .triggeredAt)
        try container.encode(hookEvent, forKey: .hookEvent)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(ThreadId.self, forKey: .sessionId)
        cwd = try container.decode(AbsolutePathBuf.self, forKey: .cwd)
        client = try container.decodeIfPresent(String.self, forKey: .client)
        let raw = try container.decode(String.self, forKey: .triggeredAt)
        guard let date = parseRFC3339SecondsZ(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .triggeredAt,
                in: container,
                debugDescription: "invalid triggered_at: \(raw)"
            )
        }
        triggeredAt = date
        hookEvent = try container.decode(HookPayloadEvent.self, forKey: .hookEvent)
    }
}

extension HookPayloadEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case threadId = "thread_id"
        case turnId = "turn_id"
        case inputMessages = "input_messages"
        case lastAssistantMessage = "last_assistant_message"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .afterAgent(let event):
            try container.encode("after_agent", forKey: .eventType)
            try container.encode(event.threadId, forKey: .threadId)
            try container.encode(event.turnId, forKey: .turnId)
            try container.encode(event.inputMessages, forKey: .inputMessages)
            try container.encodeIfPresent(event.lastAssistantMessage, forKey: .lastAssistantMessage)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .eventType)
        switch type_ {
        case "after_agent":
            self = .afterAgent(
                HookEventAfterAgent(
                    threadId: try container.decode(ThreadId.self, forKey: .threadId),
                    turnId: try container.decode(String.self, forKey: .turnId),
                    inputMessages: try container.decode([String].self, forKey: .inputMessages),
                    lastAssistantMessage: try container.decodeIfPresent(
                        String.self,
                        forKey: .lastAssistantMessage
                    )
                )
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .eventType,
                in: container,
                debugDescription: "Unknown HookEvent: \(type_)"
            )
        }
    }
}

private func rfc3339SecondsZ(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    let formatted = formatter.string(from: date)
    if let dot = formatted.firstIndex(of: ".") {
        return String(formatted[..<dot]) + "Z"
    }
    return formatted
}

private func parseRFC3339SecondsZ(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
}
