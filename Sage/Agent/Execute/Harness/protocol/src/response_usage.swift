//
//  response_usage.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/response_usage.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Per-response usage metadata reported by the upstream service, without
//  aggregation. `serde_json::Value` maps to `JSONValue`.
//

import Foundation

/// Usage metadata reported for one upstream response.
public struct ResponseUsageMetadata: Equatable, Sendable {
    public var amount: String?
    public var metadata: JSONValue?

    public init(amount: String? = nil, metadata: JSONValue? = nil) {
        self.amount = amount
        self.metadata = metadata
    }
}

extension ResponseUsageMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case amount
        case metadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decodeIfPresent(String.self, forKey: .amount)
        metadata = try container.decodeIfPresent(JSONValue.self, forKey: .metadata)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // serde serializes `None` as an explicit null (no skip_serializing_if).
        try container.encode(amount, forKey: .amount)
        try container.encode(metadata, forKey: .metadata)
    }
}
