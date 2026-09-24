//
//  serde_helpers.swift
//  CodexProtocol
//
//  Sage addition (no codex counterpart).
//
//  Shared Codable helpers reproducing serde attributes that Swift's
//  synthesized conformance does not cover:
//  - `deny_unknown_fields` → `rejectUnknownFields(in:type:)`
//  - `BTreeMap` sorted-key encoding → `encodeSorted(_:)`
//  - chrono `DateTime<Utc>` RFC 3339 strings → `RFC3339`
//

import Foundation

/// serde `deny_unknown_fields`: fail decoding when the payload carries keys
/// outside `allowed`.
///
/// NOTE: must read keys through `JSONCodingKey` — with a raw-value enum
/// `CodingKeys`, `allKeys` silently drops unknown keys (their
/// `init?(stringValue:)` returns nil), which would defeat the check.
func rejectUnknownFields<Keys: CodingKey & Hashable>(
    in decoder: any Decoder,
    allowed: Set<Keys>,
    type: String
) throws {
    let raw = try decoder.container(keyedBy: JSONCodingKey.self)
    let allowedNames = Set(allowed.map(\.stringValue))
    for key in raw.allKeys where !allowedNames.contains(key.stringValue) {
        let expected = allowedNames.sorted().joined(separator: ", ")
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "unknown field `\(key.stringValue)` for \(type), expected \(expected)"
            )
        )
    }
}

/// Convenience for types whose `CodingKeys` are `CaseIterable`.
func rejectUnknownFields<Keys: CodingKey & CaseIterable & Hashable>(
    in decoder: any Decoder,
    keys: Keys.Type,
    type: String
) throws {
    try rejectUnknownFields(in: decoder, allowed: Set(Keys.allCases), type: type)
}

extension JSONValue {
    /// Re-decode this value as `T`. Mirrors serde's untagged-enum fallback:
    /// buffer the content, then try each variant in declaration order.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension KeyedEncodingContainer where Key == JSONCodingKey {
    /// serde_json serializes `BTreeMap` with keys in sorted order.
    mutating func encodeSorted<Value: Encodable>(_ dictionary: [String: Value]) throws {
        for key in dictionary.keys.sorted() {
            try encode(dictionary[key], forKey: JSONCodingKey(key))
        }
    }
}

/// chrono `DateTime<Utc>` serde format: RFC 3339 / ISO 8601.
///
/// Known gap: chrono emits up to nanosecond precision;
/// `ISO8601DateFormatter` reliably round-trips millisecond precision.
enum RFC3339 {
    static func encode(_ date: Date) -> String {
        ISO8601DateFormatter.withFractionalSeconds.string(from: date)
    }

    static func decode(_ string: String) throws -> Date {
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string)
            ?? ISO8601DateFormatter.internetDateTime.date(from: string) {
            return date
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "invalid RFC 3339 timestamp: \(string)"
            )
        )
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
