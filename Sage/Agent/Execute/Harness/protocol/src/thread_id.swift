//
//  thread_id.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/thread_id.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  UUIDv7-backed thread identifier, wire-encoded as a string. `RolloutId` is
//  the same representation (a `thread/revert` rollout file gets a fresh
//  rollout id while keeping the thread id).
//

import Foundation

/// Identifier for a Codex thread.
///
/// Codex-generated thread IDs are UUIDv7, and some use cases rely on that.
public struct ThreadId: Hashable, Sendable {
    let uuid: UUID

    /// `ThreadId::new` — UUIDv7.
    public init() {
        uuid = UUIDv7.now()
    }

    /// `ThreadId::from_u128` — construct from the 128-bit representation.
    public init(u128 value: UInt128) {
        uuid = UUID(uuid: (
            UInt8((value >> 120) & 0xFF), UInt8((value >> 112) & 0xFF),
            UInt8((value >> 104) & 0xFF), UInt8((value >> 96) & 0xFF),
            UInt8((value >> 88) & 0xFF), UInt8((value >> 80) & 0xFF),
            UInt8((value >> 72) & 0xFF), UInt8((value >> 64) & 0xFF),
            UInt8((value >> 56) & 0xFF), UInt8((value >> 48) & 0xFF),
            UInt8((value >> 40) & 0xFF), UInt8((value >> 32) & 0xFF),
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ))
    }

    /// `ThreadId::from_string`.
    public static func fromString(_ string: String) throws -> ThreadId {
        ThreadId(uuid: try UUIDv7.parse(string))
    }

    init(uuid: UUID) {
        self.uuid = uuid
    }
}

/// Identifier encoded in a rollout filename. Same representation as `ThreadId`.
public typealias RolloutId = ThreadId

extension ThreadId {
    /// `From<SessionId> for ThreadId`.
    public init(_ sessionId: SessionId) {
        self.init(uuid: sessionId.uuid)
    }

    public init(fromString value: String) throws {
        self = try ThreadId.fromString(value)
    }
}

extension ThreadId: CustomStringConvertible {
    public var description: String {
        uuid.uuidString.lowercased()
    }
}

extension ThreadId: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = try ThreadId.fromString(value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
