//
//  lib.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  JSONL decode is faithful. Recorder/list/compression files fill the rest
//  of the crate.
//

import CodexHistory
import CodexProtocol
import Foundation

public let SESSIONS_SUBDIR = "sessions"
public let ARCHIVED_SESSIONS_SUBDIR = "archived_sessions"

public let INTERACTIVE_SESSION_SOURCES: [SessionSource] = [
    .cli, .vsCode, .custom("atlas"), .custom("chatgpt"),
]

/// Decodes a persisted rollout record without flattened-envelope buffering.
public func decodeRolloutLine(_ value: JSONValue) throws -> RolloutLine {
    guard case .object(var fields) = value else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "rollout line must be a JSON object"))
    }
    guard let timestampValue = fields.removeValue(forKey: "timestamp") else {
        throw DecodingError.keyNotFound(
            JSONCodingKey("timestamp"),
            .init(codingPath: [], debugDescription: "timestamp"))
    }
    let timestamp = timestampValue.stringValue ?? ""
    let ordinal = fields.removeValue(forKey: "ordinal").flatMap { $0.intValue }.map(UInt64.init)
    let item = try JSONDecoder().decode(RolloutItem.self, from: try JSONEncoder().encode(JSONValue.object(fields)))
    return RolloutLine(timestamp: timestamp, ordinal: ordinal, item: item)
}

public func parseRolloutLine(_ line: String) throws -> RolloutLine {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    return try decodeRolloutLine(value)
}

public func parseRolloutLineBytes(_ bytes: Data) throws -> RolloutLine {
    let value = try JSONDecoder().decode(JSONValue.self, from: bytes)
    return try decodeRolloutLine(value)
}

/// Encodes a rollout record as the flattened JSON object persisted on disk.
public func encodeRolloutLine(_ line: RolloutLine) throws -> JSONValue {
    let itemData = try JSONEncoder().encode(line.item)
    guard case .object(var fields) = try JSONDecoder().decode(JSONValue.self, from: itemData) else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "RolloutItem must encode as a JSON object"))
    }
    fields["timestamp"] = .string(line.timestamp)
    if let ordinal = line.ordinal {
        fields["ordinal"] = .uint(ordinal)
    }
    return .object(fields)
}

public func encodeRolloutLineString(_ line: RolloutLine) throws -> String {
    try encodeRolloutLine(line).encodedString()
}

private struct JSONCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
