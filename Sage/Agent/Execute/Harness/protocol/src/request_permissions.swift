//
//  request_permissions.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/request_permissions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Request-permissions tool wire types. `schemars`/`ts_rs` derives are not
//  ported. `LegacyAppPathString` comes from CodexUtils (the protocol crate
//  depends on the utils crates upstream).
//

import CodexUtils
import Foundation

public enum PermissionGrantScope: String, Codable, Equatable, Sendable {
    case turn
    case session

    /// `#[default]` upstream.
    public static let `default`: PermissionGrantScope = .turn
}

public struct RequestPermissionProfile: Codable, Equatable, Sendable {
    public var network: NetworkPermissions?
    public var fileSystem: FileSystemPermissions?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case network
        case fileSystem = "file_system"
    }

    public var isEmpty: Bool {
        network == nil && fileSystem == nil
    }

    public init(network: NetworkPermissions? = nil, fileSystem: FileSystemPermissions? = nil) {
        self.network = network
        self.fileSystem = fileSystem
    }

    /// serde `deny_unknown_fields`.
    public init(from decoder: any Decoder) throws {
        try rejectUnknownFields(
            in: decoder, keys: CodingKeys.self, type: "RequestPermissionProfile")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decodeIfPresent(NetworkPermissions.self, forKey: .network)
        fileSystem = try container.decodeIfPresent(FileSystemPermissions.self, forKey: .fileSystem)
    }
}

/// `From<RequestPermissionProfile> for AdditionalPermissionProfile`.
extension AdditionalPermissionProfile {
    public init(_ value: RequestPermissionProfile) {
        self.init(network: value.network, fileSystem: value.fileSystem)
    }
}

/// `From<AdditionalPermissionProfile> for RequestPermissionProfile`.
extension RequestPermissionProfile {
    public init(_ value: AdditionalPermissionProfile) {
        self.init(network: value.network, fileSystem: value.fileSystem)
    }
}

public struct RequestPermissionsArgs: Codable, Equatable, Sendable {
    /// Serialized as `environment_id`; `environmentId` accepted as an alias.
    public var environmentId: String?
    public var reason: String?
    public var permissions: RequestPermissionProfile

    private enum CodingKeys: String, CodingKey {
        case environmentId = "environment_id"
        case environmentIdAlias = "environmentId"
        case reason, permissions
    }

    public init(
        environmentId: String? = nil, reason: String? = nil,
        permissions: RequestPermissionProfile
    ) {
        self.environmentId = environmentId
        self.reason = reason
        self.permissions = permissions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        environmentId = try container.decodeIfPresent(String.self, forKey: .environmentId)
            ?? container.decodeIfPresent(String.self, forKey: .environmentIdAlias)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        permissions = try container.decode(RequestPermissionProfile.self, forKey: .permissions)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // `skip_serializing_if = "Option::is_none"`
        try container.encodeIfPresent(environmentId, forKey: .environmentId)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(permissions, forKey: .permissions)
    }
}

public struct RequestPermissionsResponse: Codable, Equatable, Sendable {
    public var permissions: RequestPermissionProfile
    public var scope: PermissionGrantScope
    /// Review subsequent commands in this turn unless a permission hook
    /// resolves the request.
    public var strictAutoReview: Bool

    private enum CodingKeys: String, CodingKey {
        case permissions, scope
        case strictAutoReview = "strict_auto_review"
    }

    public init(
        permissions: RequestPermissionProfile,
        scope: PermissionGrantScope = .turn,
        strictAutoReview: Bool = false
    ) {
        self.permissions = permissions
        self.scope = scope
        self.strictAutoReview = strictAutoReview
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permissions = try container.decode(RequestPermissionProfile.self, forKey: .permissions)
        scope = try container.decodeIfPresent(PermissionGrantScope.self, forKey: .scope) ?? .turn
        strictAutoReview =
            try container.decodeIfPresent(Bool.self, forKey: .strictAutoReview) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(scope, forKey: .scope)
        // `skip_serializing_if = "std::ops::Not::not"`
        if strictAutoReview {
            try container.encode(strictAutoReview, forKey: .strictAutoReview)
        }
    }
}

public struct RequestPermissionsEvent: Codable, Equatable, Sendable {
    /// Responses API call id for the associated tool call, if available.
    public var callId: String
    /// Turn ID that this request belongs to.
    /// Uses `#[serde(default)]` for backwards compatibility.
    public var turnId: String
    /// Serialized as `environmentId`; `environment_id` accepted as an alias.
    public var environmentId: String?
    public var startedAtMs: Int64
    public var reason: String?
    public var permissions: RequestPermissionProfile
    public var cwd: LegacyAppPathString?

    private enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case turnId = "turn_id"
        case environmentId
        case environmentIdAlias = "environment_id"
        case startedAtMs = "started_at_ms"
        case reason, permissions, cwd
    }

    public init(
        callId: String,
        turnId: String = "",
        environmentId: String? = nil,
        startedAtMs: Int64,
        reason: String? = nil,
        permissions: RequestPermissionProfile,
        cwd: LegacyAppPathString? = nil
    ) {
        self.callId = callId
        self.turnId = turnId
        self.environmentId = environmentId
        self.startedAtMs = startedAtMs
        self.reason = reason
        self.permissions = permissions
        self.cwd = cwd
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
        environmentId = try container.decodeIfPresent(String.self, forKey: .environmentId)
            ?? container.decodeIfPresent(String.self, forKey: .environmentIdAlias)
        startedAtMs = try container.decode(Int64.self, forKey: .startedAtMs)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        permissions = try container.decode(RequestPermissionProfile.self, forKey: .permissions)
        cwd = try container.decodeIfPresent(LegacyAppPathString.self, forKey: .cwd)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(callId, forKey: .callId)
        try container.encode(turnId, forKey: .turnId)
        try container.encodeIfPresent(environmentId, forKey: .environmentId)
        try container.encode(startedAtMs, forKey: .startedAtMs)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(permissions, forKey: .permissions)
        try container.encodeIfPresent(cwd, forKey: .cwd)
    }
}
