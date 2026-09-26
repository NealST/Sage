//
//  backfill_state.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/backfill_state.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  sqlx row mapping is omitted. `DateTime<Utc>` maps to `Date`.
//

import Foundation

/// Persisted lifecycle state for rollout metadata backfill.
public struct BackfillState: Codable, Equatable, Sendable {
    /// Current lifecycle status.
    public var status: BackfillStatus
    /// Last processed rollout watermark.
    public var lastWatermark: String?
    /// Last successful completion time.
    public var lastSuccessAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case lastWatermark = "last_watermark"
        case lastSuccessAt = "last_success_at"
    }

    public init(
        status: BackfillStatus = .pending,
        lastWatermark: String? = nil,
        lastSuccessAt: Date? = nil
    ) {
        self.status = status
        self.lastWatermark = lastWatermark
        self.lastSuccessAt = lastSuccessAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(BackfillStatus.self, forKey: .status)
        lastWatermark = try container.decodeIfPresent(String.self, forKey: .lastWatermark)
        if let raw = try container.decodeIfPresent(String.self, forKey: .lastSuccessAt) {
            lastSuccessAt = try stateDecodeRFC3339(raw)
        } else {
            lastSuccessAt = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(lastWatermark, forKey: .lastWatermark)
        if let lastSuccessAt {
            try container.encode(stateEncodeRFC3339(lastSuccessAt), forKey: .lastSuccessAt)
        }
    }
}

/// Backfill lifecycle status.
public enum BackfillStatus: String, Codable, Equatable, Sendable {
    case pending
    case running
    case complete

    public var asStr: String { rawValue }

    public static func parse(_ value: String) throws -> BackfillStatus {
        guard let status = BackfillStatus(rawValue: value) else {
            throw StateModelError("invalid backfill status: \(value)")
        }
        return status
    }
}
