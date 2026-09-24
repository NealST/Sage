//
//  security_risk.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/security_risk.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  A thread-owned, in-memory snapshot of security risk classifier scores.
//
//  Scores must not enter model-visible conversation context or user-visible
//  thread item projections.
//
//  `BTreeMap` encodes with sorted keys; chrono `DateTime<Utc>` is an RFC 3339
//  string. The `schemars` derive carries no runtime semantics and is not ported.
//

import Foundation

public struct SecurityRiskScore: Equatable, Sendable {
    public var scores: [String: Double]
    /// The tool call whose action produced this score, when available.
    public var callId: String?
    /// The bounded tool action that was reviewed to produce this score.
    public var action: JSONValue?
    /// When sampling started, if this snapshot was written by a timestamp-aware client.
    public var sampledAt: Date?

    public init(
        scores: [String: Double],
        callId: String? = nil,
        action: JSONValue? = nil,
        sampledAt: Date? = nil
    ) {
        self.scores = scores
        self.callId = callId
        self.action = action
        self.sampledAt = sampledAt
    }
}

extension SecurityRiskScore: Codable {
    private enum CodingKeys: String, CodingKey {
        case scores
        case callId = "call_id"
        case action
        case sampledAt = "sampled_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scores = try container.decode([String: Double].self, forKey: .scores)
        // `#[serde(default, skip_serializing_if = "Option::is_none")]`.
        callId = try container.decodeIfPresent(String.self, forKey: .callId)
        action = try container.decodeIfPresent(JSONValue.self, forKey: .action)
        if let timestamp = try container.decodeIfPresent(String.self, forKey: .sampledAt) {
            sampledAt = try RFC3339.decode(timestamp)
        } else {
            sampledAt = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var scoresContainer = container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: .scores)
        try scoresContainer.encodeSorted(scores)
        try container.encodeIfPresent(callId, forKey: .callId)
        try container.encodeIfPresent(action, forKey: .action)
        if let sampledAt {
            try container.encode(RFC3339.encode(sampledAt), forKey: .sampledAt)
        }
    }
}
