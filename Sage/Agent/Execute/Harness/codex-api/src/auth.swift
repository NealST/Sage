//
//  auth.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/auth.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `http::HeaderMap` maps to `[String: String]` (lowercase names).
//  `codex_client::Request` signing is applied as header mutation on
//  `URLRequest`. ChatGPT / OAuth providers are deferred; this port ships
//  `AuthProvider` plus `BearerAuthProvider` (API key).
//

import Foundation

/// Error returned while applying authentication to an outbound request.
public enum AuthError: Error, Equatable, Sendable {
    case build(String)
    case transient(String)
}

extension AuthError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .build(let message):
            return "request auth build error: \(message)"
        case .transient(let message):
            return "transient auth error: \(message)"
        }
    }
}

extension TransportError {
    public init(_ error: AuthError) {
        switch error {
        case .build(let message):
            self = .build(message)
        case .transient(let message):
            self = .network(message)
        }
    }
}

/// Applies authentication to API requests.
///
/// Header-only providers can implement `addAuthHeaders`; providers that sign
/// complete requests can override `applyAuth`.
public protocol AuthProvider: Sendable {
    /// Adds any auth headers that are available without request body access.
    func addAuthHeaders(_ headers: inout [String: String])

    /// Returns any auth headers that are available without request body access.
    func toAuthHeaders() -> [String: String]

    /// Resolves auth headers for an outbound request. Implementations may
    /// refresh credentials asynchronously.
    func resolveAuthHeaders() async throws -> [String: String]

    /// Applies auth to a complete outbound request and returns the request to send.
    func applyAuth(_ request: URLRequest) async throws -> URLRequest
}

extension AuthProvider {
    public func toAuthHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        addAuthHeaders(&headers)
        return headers
    }

    public func resolveAuthHeaders() async throws -> [String: String] {
        toAuthHeaders()
    }

    public func applyAuth(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        let headers = try await resolveAuthHeaders()
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}

/// Shared auth handle passed through API clients.
public typealias SharedAuthProvider = any AuthProvider

/// API-key bearer auth. ChatGPT / OAuth providers are deferred.
public struct BearerAuthProvider: AuthProvider, Sendable {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func addAuthHeaders(_ headers: inout [String: String]) {
        headers["authorization"] = "Bearer \(apiKey)"
    }
}

public struct AgentIdentityTelemetry: Equatable, Sendable {
    public var agentId: String
    public var taskId: String

    public init(agentId: String, taskId: String) {
        self.agentId = agentId
        self.taskId = taskId
    }
}

public struct AuthHeaderTelemetry: Equatable, Sendable {
    public var attached: Bool
    public var name: String?

    public init(attached: Bool = false, name: String? = nil) {
        self.attached = attached
        self.name = name
    }
}

public func authHeaderTelemetry(_ auth: any AuthProvider) -> AuthHeaderTelemetry {
    var headers: [String: String] = [:]
    auth.addAuthHeaders(&headers)
    let name = headers.keys.contains(where: { $0.caseInsensitiveCompare("authorization") == .orderedSame })
        ? "authorization"
        : nil
    return AuthHeaderTelemetry(attached: name != nil, name: name)
}
