//
//  session_id.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/session_id.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  UUIDv7-backed session identifier, wire-encoded as a string. The schemars /
//  ts_rs schema derives are compile-time exports with no runtime semantics
//  and are not ported.
//

import Foundation

public struct SessionId: Hashable, Sendable {
    let uuid: UUID

    /// `SessionId::new` — UUIDv7, time-ordered like upstream.
    public init() {
        uuid = UUIDv7.now()
    }

    /// `SessionId::from_string`.
    public static func fromString(_ string: String) throws -> SessionId {
        SessionId(uuid: try UUIDv7.parse(string))
    }

    init(uuid: UUID) {
        self.uuid = uuid
    }
}

extension SessionId {
    /// `From<ThreadId> for SessionId`.
    public init(_ threadId: ThreadId) {
        self.init(uuid: threadId.uuid)
    }

    /// `From<SessionId> for String` — use `String(describing:)` or `description`.
    public init(fromString value: String) throws {
        self = try SessionId.fromString(value)
    }
}

extension SessionId: CustomStringConvertible {
    public var description: String {
        uuid.uuidString.lowercased()
    }
}

extension SessionId: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = try SessionId.fromString(value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
