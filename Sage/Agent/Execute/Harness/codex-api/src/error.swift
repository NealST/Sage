//
//  error.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/error.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `codex_client::TransportError` is defined locally (no HTTP-client crate).
//  `http::StatusCode` maps to `UInt16`. Display strings match upstream.
//

import CodexProtocol
import Foundation

/// Local stand-in for `codex_client::TransportError`.
public enum TransportError: Error, Equatable, Sendable {
    case http(
        status: UInt16,
        url: String?,
        headers: [String: String]?,
        body: String?,
        retryAfter: RetryAfter?
    )
    case retryLimit
    case timeout
    case policy(String)
    case connection(HttpError)
    case network(String)
    case build(String)
    case responseTooLarge(limit: Int, actual: Int)
}

extension TransportError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .http(let status, let url, _, let body, _):
            let urlPart = url.map { " \($0)" } ?? ""
            let bodyPart = body.map { ": \($0)" } ?? ""
            return "http \(status)\(urlPart)\(bodyPart)"
        case .retryLimit:
            return "retry limit reached"
        case .timeout:
            return "request timed out"
        case .policy(let denied):
            return denied
        case .connection(let source):
            return "connection failed: \(source)"
        case .network(let message):
            return message
        case .build(let message):
            return message
        case .responseTooLarge(let limit, let actual):
            return "response too large: \(actual) bytes exceeds limit of \(limit)"
        }
    }
}

public enum ApiError: Error, Equatable, Sendable {
    case transport(TransportError)
    case api(status: UInt16, message: String)
    case stream(String)
    case contextWindowExceeded
    case quotaExceeded
    case usageNotIncluded
    case retryable(message: String, retryAfter: RetryAfter?)
    case rateLimitExceeded(message: String, retryAfter: RetryAfter?)
    case rateLimit(String)
    case invalidRequest(message: String)
    case invalidPrompt(message: String)
    case cyberPolicy(message: String)
    case bioPolicy(message: String)
    case misalignmentPolicyViolation(message: String, misalignment: MisalignmentErrorDetails?)
    case flexUnavailable
    case serverOverloaded(retryAfter: RetryAfter?)
}

extension ApiError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .transport(let error):
            return error.description
        case .api(let status, let message):
            return "api error \(status): \(message)"
        case .stream(let message):
            return "stream error: \(message)"
        case .contextWindowExceeded:
            return "context window exceeded"
        case .quotaExceeded:
            return "quota exceeded"
        case .usageNotIncluded:
            return "usage not included"
        case .retryable(let message, _):
            return "retryable error: \(message)"
        case .rateLimitExceeded(let message, _):
            return "rate limit exceeded: \(message)"
        case .rateLimit(let message):
            return "rate limit: \(message)"
        case .invalidRequest(let message):
            return "invalid request: \(message)"
        case .invalidPrompt(let message):
            return "invalid prompt: \(message)"
        case .cyberPolicy(let message):
            return "cyber policy: \(message)"
        case .bioPolicy(let message):
            return "bio policy: \(message)"
        case .misalignmentPolicyViolation(let message, _):
            return "misalignment policy violation: \(message)"
        case .flexUnavailable:
            return "Flex capacity unavailable."
        case .serverOverloaded:
            return "server overloaded"
        }
    }
}

func parseFlexUnavailable(_ error: JSONValue) -> ApiError? {
    guard error.objectValue?["code"]?.stringValue == "flex_unavailable" else {
        return nil
    }
    return .flexUnavailable
}
