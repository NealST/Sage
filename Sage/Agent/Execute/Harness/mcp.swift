//
//  mcp.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Transport uses Sage MCPStdioClient. This is the harness projection
//  of configured servers and environment authority.
//

import Foundation

public let defaultMcpServerEnvironmentId = "local"
public let legacyCodexAppsRegistrationId = "legacy_codex_apps"

public enum McpEnvironmentAuthority: Equatable, Sendable {
    case unrestricted
    case selectedPluginsOnly
    case unavailable
    case restricted
}

public struct McpRuntimeProjection: Equatable, Sendable {
    public var pluginsAvailable: Bool
    public var serverNames: [String]

    public init(pluginsAvailable: Bool = false, serverNames: [String] = []) {
        self.pluginsAvailable = pluginsAvailable
        self.serverNames = serverNames
    }
}

public enum McpEnvironmentScope: Equatable, Sendable {
    case hostOnly
    case selected([String])

    public func authorityFor(environmentId: String) -> McpEnvironmentAuthority {
        switch self {
        case .hostOnly:
            return .unrestricted
        case .selected(let ids):
            if ids.contains(environmentId) { return .unrestricted }
            return environmentId == defaultMcpServerEnvironmentId
                ? .unrestricted
                : .selectedPluginsOnly
        }
    }
}
