//
//  codex_error_info.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/codex_error_info.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `Codable` for `CodexErrorInfo` (the enum itself lives in protocol.swift,
//  mirroring protocol.rs). Decodes unknown error classifications as `other`
//  so enclosing records stay readable; serialization stays exhaustive and
//  known payload validation stays strict. Wire format is serde's external
//  tagging: unit variants are bare strings ("context_window_exceeded") and
//  struct variants are single-key objects
//  ({"http_connection_failed": {"http_status_code": 400}}).
//

import Foundation

extension CodexErrorInfo: Codable {
    /// Unit-variant wire tags in upstream declaration order
    /// (`CodexErrorInfoWire`, snake_case).
    private static let unitTags: [String: CodexErrorInfo] = [
        "context_window_exceeded": .contextWindowExceeded,
        "session_budget_exceeded": .sessionBudgetExceeded,
        "usage_limit_exceeded": .usageLimitExceeded,
        "rate_limit_exceeded": .rateLimitExceeded,
        "flex_unavailable": .flexUnavailable,
        "server_overloaded": .serverOverloaded,
        "cyber_policy": .cyberPolicy,
        "bio_policy": .bioPolicy,
        "misalignment_policy_violation": .misalignmentPolicyViolation,
        "internal_server_error": .internalServerError,
        "unauthorized": .unauthorized,
        "bad_request": .badRequest,
        "invalid_prompt": .invalidPrompt,
        "sandbox_error": .sandboxError,
        "thread_rollback_failed": .threadRollbackFailed,
        "other": .other,
    ]

    /// Struct-variant wire tags (payload-carrying variants).
    private static let structTags: Set<String> = [
        "http_connection_failed",
        "response_stream_connection_failed",
        "response_stream_disconnected",
        "response_too_many_failed_attempts",
        "active_turn_not_steerable",
    ]

    private struct HTTPStatusPayload: Codable {
        var http_status_code: UInt16?
    }

    private struct TurnKindPayload: Codable {
        var turn_kind: NonSteerableTurnKind
    }

    /// Classification used by the unknown-tag probe: deserializing the tag as
    /// a unit-only wire value yields `other` exactly for unknown tags (serde
    /// `#[serde(other)]`), while known struct-variant tags reject a bare
    /// string.
    private static func tagIsUnknown(_ tag: String) -> Bool {
        unitTags[tag] == nil && !structTags.contains(tag)
    }

    public init(from decoder: any Decoder) throws {
        let value = try JSONValue(from: decoder)
        // Probe the tag first so only unknown payloads are discarded:
        // `serde(other)` recognizes unknown tags, but its unit variant rejects
        // their payloads.
        if case .object(let fields) = value,
           fields.count == 1,
           let kind = fields.keys.first,
           kind != "other",
           CodexErrorInfo.tagIsUnknown(kind)
        {
            self = .other
            return
        }
        try self.init(wire: value)
    }

    private init(wire value: JSONValue) throws {
        switch value {
        case .string(let tag):
            // External tagging: a bare string denotes a unit variant. Known
            // struct-variant tags reject strings; unknown tags map to `other`.
            if let unit = CodexErrorInfo.unitTags[tag] {
                self = unit
            } else if CodexErrorInfo.structTags.contains(tag) {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription:
                            "invalid type: string, expected struct variant \(tag)"
                    ))
            } else {
                self = .other
            }
        case .object(let fields) where fields.count == 1:
            let tag = fields.keys.first!
            let payload = fields[tag] ?? .null
            switch tag {
            case "http_connection_failed":
                self = .httpConnectionFailed(
                    httpStatusCode: try payload.decoded(as: HTTPStatusPayload.self)
                        .http_status_code)
            case "response_stream_connection_failed":
                self = .responseStreamConnectionFailed(
                    httpStatusCode: try payload.decoded(as: HTTPStatusPayload.self)
                        .http_status_code)
            case "response_stream_disconnected":
                self = .responseStreamDisconnected(
                    httpStatusCode: try payload.decoded(as: HTTPStatusPayload.self)
                        .http_status_code)
            case "response_too_many_failed_attempts":
                self = .responseTooManyFailedAttempts(
                    httpStatusCode: try payload.decoded(as: HTTPStatusPayload.self)
                        .http_status_code)
            case "active_turn_not_steerable":
                self = .activeTurnNotSteerable(
                    turnKind: try payload.decoded(as: TurnKindPayload.self).turn_kind)
            default:
                // Unit variant in map form: serde_json expects a null payload.
                if let unit = CodexErrorInfo.unitTags[tag] {
                    guard case .null = payload else {
                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(
                                codingPath: [],
                                debugDescription:
                                    "invalid type: non-null payload, expected unit variant \(tag)"
                            ))
                    }
                    self = unit
                } else {
                    // Unreachable: the probe in `init(from:)` already mapped
                    // unknown single-key objects to `other`.
                    self = .other
                }
            }
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "expected string or single-key object for CodexErrorInfo"
                ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .httpConnectionFailed(let code):
            try Self.encodeStructVariant(
                "http_connection_failed",
                payload: HTTPStatusPayload(http_status_code: code), to: encoder)
        case .responseStreamConnectionFailed(let code):
            try Self.encodeStructVariant(
                "response_stream_connection_failed",
                payload: HTTPStatusPayload(http_status_code: code), to: encoder)
        case .responseStreamDisconnected(let code):
            try Self.encodeStructVariant(
                "response_stream_disconnected",
                payload: HTTPStatusPayload(http_status_code: code), to: encoder)
        case .responseTooManyFailedAttempts(let code):
            try Self.encodeStructVariant(
                "response_too_many_failed_attempts",
                payload: HTTPStatusPayload(http_status_code: code), to: encoder)
        case .activeTurnNotSteerable(let turnKind):
            try Self.encodeStructVariant(
                "active_turn_not_steerable",
                payload: TurnKindPayload(turn_kind: turnKind), to: encoder)
        default:
            // Unit variants encode as bare snake_case strings.
            var container = encoder.singleValueContainer()
            try container.encode(unitWireTag)
        }
    }

    /// snake_case wire tag for unit variants; `nil` for payload variants.
    private var unitWireTag: String {
        switch self {
        case .contextWindowExceeded: return "context_window_exceeded"
        case .sessionBudgetExceeded: return "session_budget_exceeded"
        case .usageLimitExceeded: return "usage_limit_exceeded"
        case .rateLimitExceeded: return "rate_limit_exceeded"
        case .flexUnavailable: return "flex_unavailable"
        case .serverOverloaded: return "server_overloaded"
        case .cyberPolicy: return "cyber_policy"
        case .bioPolicy: return "bio_policy"
        case .misalignmentPolicyViolation: return "misalignment_policy_violation"
        case .internalServerError: return "internal_server_error"
        case .unauthorized: return "unauthorized"
        case .badRequest: return "bad_request"
        case .invalidPrompt: return "invalid_prompt"
        case .sandboxError: return "sandbox_error"
        case .threadRollbackFailed: return "thread_rollback_failed"
        case .other: return "other"
        default: return "other" // payload variants never reach this path
        }
    }

    private static func encodeStructVariant(
        _ tag: String,
        payload: some Encodable,
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(keyedBy: JSONCodingKey.self)
        try container.encode(payload, forKey: JSONCodingKey(tag))
    }
}
