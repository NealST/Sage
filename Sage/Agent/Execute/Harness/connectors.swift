//
//  connectors.swift
//  CodexCore
//
//  Port of codex-rs/core/src/connectors.rs + connectors crate AppInfo
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  AppInfo, mention slugs, and accessible-connector collection are live.
//  Live MCP listing, directory cache, and PluginsManager wiring wait on
//  Config / AuthManager / MCP runtime.
//

import CodexProtocol
import Foundation
import os

public let CODEX_APPS_MCP_SERVER_NAME = "codex_apps"
public let MCP_TOOL_CODEX_APPS_META_KEY = "codex/apps"
public let CONNECTORS_CACHE_TTL: TimeInterval = 3600
public let CONNECTORS_READY_TIMEOUT_ON_EMPTY_TOOLS: TimeInterval = 30

public struct AppInfo: Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var installUrl: String?
    public var isAccessible: Bool
    public var isEnabled: Bool
    public var pluginDisplayNames: [String]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        installUrl: String? = nil,
        isAccessible: Bool = false,
        isEnabled: Bool = true,
        pluginDisplayNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.installUrl = installUrl
        self.isAccessible = isAccessible
        self.isEnabled = isEnabled
        self.pluginDisplayNames = pluginDisplayNames
    }
}

public struct AccessibleConnectorsStatus: Equatable, Sendable {
    public var connectors: [AppInfo]
    public var codexAppsReady: Bool

    public init(connectors: [AppInfo], codexAppsReady: Bool) {
        self.connectors = connectors
        self.codexAppsReady = codexAppsReady
    }
}

public func connectorDisplayLabel(_ connector: AppInfo) -> String {
    connector.name
}

public func connectorMentionSlug(_ connector: AppInfo) -> String {
    connectorNameSlug(connectorDisplayLabel(connector))
}

public func connectorNameSlug(_ name: String) -> String {
    var normalized = ""
    normalized.reserveCapacity(name.count)
    for character in name {
        if character.isASCII && (character.isLetter || character.isNumber) {
            normalized.append(character.lowercased())
        } else {
            normalized.append("-")
        }
    }
    let trimmed = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "app" : trimmed
}

public struct AccessibleConnectorTool: Equatable, Sendable {
    public var connectorId: String
    public var connectorName: String?
    public var connectorDescription: String?
    public var pluginDisplayNames: [String]

    public init(
        connectorId: String,
        connectorName: String? = nil,
        connectorDescription: String? = nil,
        pluginDisplayNames: [String] = []
    ) {
        self.connectorId = connectorId
        self.connectorName = connectorName
        self.connectorDescription = connectorDescription
        self.pluginDisplayNames = pluginDisplayNames
    }
}

public struct AccessibleConnectorsCacheKey: Equatable, Sendable {
    public var chatgptBaseUrl: String
    public var accountId: String?
    public var chatgptUserId: String?
    public var isWorkspaceAccount: Bool

    public init(
        chatgptBaseUrl: String,
        accountId: String? = nil,
        chatgptUserId: String? = nil,
        isWorkspaceAccount: Bool = false
    ) {
        self.chatgptBaseUrl = chatgptBaseUrl
        self.accountId = accountId
        self.chatgptUserId = chatgptUserId
        self.isWorkspaceAccount = isWorkspaceAccount
    }
}

private struct CachedAccessibleConnectors {
    var key: AccessibleConnectorsCacheKey
    var expiresAt: Date
    var connectors: [AppInfo]
}

private let accessibleConnectorsCache = OSAllocatedUnfairLock<CachedAccessibleConnectors?>(
    initialState: nil
)

public func normalizeConnectorValue(_ value: String?) -> String? {
    value.flatMap { trimmed in
        let trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public func connectorInstallUrl(
    name: String,
    connectorId: String,
    chatgptBaseUrl: String = "https://chatgpt.com"
) -> String {
    var chatgptOrigin = chatgptBaseUrl
    while chatgptOrigin.hasSuffix("/") {
        chatgptOrigin.removeLast()
    }
    if chatgptOrigin.hasSuffix("/backend-api") {
        chatgptOrigin.removeLast("/backend-api".count)
    }
    let slug = connectorNameSlug(name)
    return "\(chatgptOrigin)/apps/\(slug)/\(connectorId)"
}

public func collectAccessibleConnectors(_ tools: [AccessibleConnectorTool]) -> [AppInfo] {
    var connectors: [String: (AppInfo, Set<String>)] = [:]
    for tool in tools {
        let connectorId = tool.connectorId
        let connectorName = normalizeConnectorValue(tool.connectorName) ?? connectorId
        let connectorDescription = normalizeConnectorValue(tool.connectorDescription)
        if var existing = connectors[connectorId] {
            if existing.0.name == connectorId && connectorName != connectorId {
                existing.0.name = connectorName
            }
            if existing.0.description == nil, connectorDescription != nil {
                existing.0.description = connectorDescription
            }
            existing.1.formUnion(tool.pluginDisplayNames)
            connectors[connectorId] = existing
        } else {
            connectors[connectorId] = (
                AppInfo(
                    id: connectorId,
                    name: connectorName,
                    description: connectorDescription,
                    isAccessible: true,
                    isEnabled: true
                ),
                Set(tool.pluginDisplayNames)
            )
        }
    }
    var accessible = connectors.values.map { connector, pluginDisplayNames -> AppInfo in
        var connector = connector
        connector.pluginDisplayNames = pluginDisplayNames.sorted()
        connector.installUrl = connectorInstallUrl(name: connector.name, connectorId: connector.id)
        return connector
    }
    accessible.sort { left, right in
        if left.isAccessible != right.isAccessible {
            return left.isAccessible && !right.isAccessible
        }
        if left.name != right.name {
            return left.name < right.name
        }
        return left.id < right.id
    }
    return accessible
}

public func accessibleConnectorsFromMcpTools(_ tools: [AccessibleConnectorTool]) -> [AppInfo] {
    collectAccessibleConnectors(tools)
}

public func withAppPluginSources(
    _ connectors: [AppInfo],
    pluginDisplayNamesByConnectorId: [String: [String]]
) -> [AppInfo] {
    connectors.map { connector in
        var connector = connector
        if let names = pluginDisplayNamesByConnectorId[connector.id] {
            connector.pluginDisplayNames = names
        }
        return connector
    }
}

public func readCachedAccessibleConnectors(_ key: AccessibleConnectorsCacheKey) -> [AppInfo]? {
    accessibleConnectorsCache.withLock { cache in
        let now = Date()
        guard let cached = cache else { return nil }
        if now < cached.expiresAt && cached.key == key {
            return cached.connectors
        }
        if now >= cached.expiresAt {
            cache = nil
        }
        return nil
    }
}

public func writeCachedAccessibleConnectors(
    _ key: AccessibleConnectorsCacheKey,
    connectors: [AppInfo]
) {
    accessibleConnectorsCache.withLock { cache in
        cache = CachedAccessibleConnectors(
            key: key,
            expiresAt: Date().addingTimeInterval(CONNECTORS_CACHE_TTL),
            connectors: connectors
        )
    }
}

public func listAccessibleConnectorsFromMcpTools() async throws -> [AppInfo] {
    throw CodexErr.unsupportedOperation(
        "list_accessible_connectors_from_mcp_tools waits on Config / MCP / AuthManager"
    )
}

public func listCachedAccessibleConnectorsFromMcpTools() -> [AppInfo]? {
    nil
}
