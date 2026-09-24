//
//  uuid_v7.swift
//  CodexProtocol
//
//  Sage addition (no codex counterpart).
//
//  UUIDv7 generator backing `ThreadId` / `SessionId`. Codex calls the `uuid`
//  crate's `Uuid::now_v7()`; Foundation only offers random (v4) UUIDs, so the
//  v7 layout is implemented here per RFC 9562 §5.7:
//  48-bit unix epoch milliseconds, version 7, 12-bit random, variant 0b10,
//  62-bit random.
//

import Foundation

/// Error parsing a UUID from a string, mirroring `uuid::Error` usage sites.
public enum InvalidUUIDError: Error, Equatable, CustomStringConvertible {
    case invalidString(String)

    public var description: String {
        switch self {
        case .invalidString(let value):
            return "invalid UUID string: \(value)"
        }
    }
}

enum UUIDv7 {
    /// `Uuid::now_v7()` equivalent.
    static func now() -> UUID {
        let millis = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF_FFFF
        var random = [UInt8](repeating: 0, count: 10)
        // SecRandomCopyBytes via Foundation: SystemRandomNumberGenerator is
        // cryptographically secure on Apple platforms.
        var generator = SystemRandomNumberGenerator()
        for index in random.indices {
            random[index] = UInt8.random(in: .min ... .max, using: &generator)
        }

        let bytes: [UInt8] = [
            UInt8((millis >> 40) & 0xFF),
            UInt8((millis >> 32) & 0xFF),
            UInt8((millis >> 24) & 0xFF),
            UInt8((millis >> 16) & 0xFF),
            UInt8((millis >> 8) & 0xFF),
            UInt8(millis & 0xFF),
            0x70 | (random[0] & 0x0F), // version 7 + high nibble of rand_a
            random[1],
            0x80 | (random[2] & 0x3F), // variant 0b10 + high 6 bits of rand_b
            random[3],
            random[4],
            random[5],
            random[6],
            random[7],
            random[8],
            random[9],
        ]
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// `Uuid::parse_str` equivalent: accepts the canonical hyphenated form.
    static func parse(_ string: String) throws -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            throw InvalidUUIDError.invalidString(string)
        }
        return uuid
    }
}
