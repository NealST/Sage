//
//  tags.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/tags.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexUtils

public let APP_VERSION_TAG = "app.version"
public let AUTH_MODE_TAG = "auth_mode"
public let MODEL_TAG = "model"
public let ORIGINATOR_TAG = "originator"
public let SERVICE_NAME_TAG = "service_name"
public let SESSION_SOURCE_TAG = "session_source"

private let otherOriginatorTagValue = "other"
private let knownOriginatorTagValues: [String] = [
    "codex_desktop",
    "codex-app-server",
    "codex_mcp_server",
    "codex_cli_rs",
    "codex-tui",
    "codex_vscode",
    "none",
    "codex_exec",
    "codex-cli",
    "codex_sdk_ts",
    "codex-app-server-sdk",
]

/// Return a known low-cardinality originator tag value, or `other`.
public func boundedOriginatorTagValue(_ originator: String) -> String {
    let sanitized = sanitizeMetricTagValue(originator)
    return knownOriginatorTagValues.contains(sanitized) ? sanitized : otherOriginatorTagValue
}

public struct SessionMetricTagValues: Sendable {
    public var authMode: String?
    public var sessionSource: String
    public var originator: String
    public var serviceName: String?
    public var model: String
    public var appVersion: String

    public init(
        authMode: String?,
        sessionSource: String,
        originator: String,
        serviceName: String?,
        model: String,
        appVersion: String
    ) {
        self.authMode = authMode
        self.sessionSource = sessionSource
        self.originator = originator
        self.serviceName = serviceName
        self.model = model
        self.appVersion = appVersion
    }

    public func intoTags() throws -> [(String, String)] {
        var tags: [(String, String)] = []
        try Self.pushOptionalTag(&tags, AUTH_MODE_TAG, authMode)
        try Self.pushOptionalTag(&tags, SESSION_SOURCE_TAG, sessionSource)
        try Self.pushOptionalTag(&tags, ORIGINATOR_TAG, originator)
        try Self.pushOptionalTag(&tags, SERVICE_NAME_TAG, serviceName)
        try Self.pushOptionalTag(&tags, MODEL_TAG, model)
        try Self.pushOptionalTag(&tags, APP_VERSION_TAG, appVersion)
        return tags
    }

    private static func pushOptionalTag(
        _ tags: inout [(String, String)],
        _ key: String,
        _ value: String?
    ) throws {
        guard let value else { return }
        try validateTagKey(key)
        try validateTagValue(value)
        tags.append((key, value))
    }
}
