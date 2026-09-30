//
//  mcp_tool_exposure.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_tool_exposure.rs (Apache-2.0)
//  plus tool_is_model_visible from codex-mcp and AppToolPolicy from
//  connectors (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Catalog filter, Apps omit, per-tool policy, and agent-plugin byte
//  budgets are live. Live McpBinding is a generation id: the cache
//  drops handlers when the id changes. Transport still waits on
//  Session.services.onMcpCall.
//

import Foundation

public let maxAgentPluginMcpSpecBytes = 8_000
public let maxAgentPluginMcpTotalBytes = 64_000

public let mcpUIMetaKey = "ui"
public let mcpUIVisibilityMetaKey = "visibility"
public let mcpUIModelVisibility = "model"

public enum McpToolExposure: Equatable, Sendable {
    case direct
    case deferred
    case hidden
}

public struct AppToolPolicy: Equatable, Sendable {
    public var enabled: Bool
    public var approval: AppToolApproval

    public init(enabled: Bool = true, approval: AppToolApproval = .auto) {
        self.enabled = enabled
        self.approval = approval
    }
}

public enum AppToolApproval: String, Equatable, Sendable {
    case auto
}

public struct AppToolPolicyInput: Equatable, Sendable {
    public var connectorId: String?
    public var linkId: String?
    public var toolName: String
    public var toolTitle: String?
    public var destructiveHint: Bool?
    public var openWorldHint: Bool?

    public init(
        connectorId: String? = nil,
        linkId: String? = nil,
        toolName: String,
        toolTitle: String? = nil,
        destructiveHint: Bool? = nil,
        openWorldHint: Bool? = nil
    ) {
        self.connectorId = connectorId
        self.linkId = linkId
        self.toolName = toolName
        self.toolTitle = toolTitle
        self.destructiveHint = destructiveHint
        self.openWorldHint = openWorldHint
    }
}

public struct AppsToolConfig: Equatable, Sendable {
    public var enabled: Bool?

    public init(enabled: Bool? = nil) {
        self.enabled = enabled
    }
}

public struct AppsAppConfig: Equatable, Sendable {
    public var enabled: Bool
    public var defaultToolsEnabled: Bool?
    public var destructiveEnabled: Bool?
    public var openWorldEnabled: Bool?
    public var tools: [String: AppsToolConfig]

    public init(
        enabled: Bool = true,
        defaultToolsEnabled: Bool? = nil,
        destructiveEnabled: Bool? = nil,
        openWorldEnabled: Bool? = nil,
        tools: [String: AppsToolConfig] = [:]
    ) {
        self.enabled = enabled
        self.defaultToolsEnabled = defaultToolsEnabled
        self.destructiveEnabled = destructiveEnabled
        self.openWorldEnabled = openWorldEnabled
        self.tools = tools
    }
}

public struct AppsConfig: Equatable, Sendable {
    public var defaultEnabled: Bool?
    public var apps: [String: AppsAppConfig]

    public init(defaultEnabled: Bool? = nil, apps: [String: AppsAppConfig] = [:]) {
        self.defaultEnabled = defaultEnabled
        self.apps = apps
    }

    public var isEmpty: Bool {
        defaultEnabled == nil && apps.isEmpty
    }
}

public struct AppToolPolicyEvaluator: Equatable, Sendable {
    public var appsConfig: AppsConfig?

    public init(appsConfig: AppsConfig? = nil) {
        self.appsConfig = appsConfig.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func policy(_ input: AppToolPolicyInput) -> AppToolPolicy {
        appToolPolicy(from: appsConfig, input: input)
    }

    public func appEnabled(_ connectorId: String) -> Bool {
        guard let appsConfig else { return true }
        return appIsEnabled(appsConfig, connectorId: connectorId)
    }
}

public struct McpToolRegistration: Equatable, Sendable {
    public var tool: McpVisibleTool
    public var exposure: McpToolExposure

    public init(tool: McpVisibleTool, exposure: McpToolExposure) {
        self.tool = tool
        self.exposure = exposure
    }
}

public struct CachedMcpHandlers: Equatable, Sendable {
    public var bindingID: UInt64
    public var toolsByName: [String: McpVisibleTool]

    public init(bindingID: UInt64, toolsByName: [String: McpVisibleTool] = [:]) {
        self.bindingID = bindingID
        self.toolsByName = toolsByName
    }
}

public struct McpHandlerCache: Equatable, Sendable {
    public var cached: CachedMcpHandlers?
    public var exposedToolNames: [String]

    public init(cached: CachedMcpHandlers? = nil, exposedToolNames: [String] = []) {
        self.cached = cached
        self.exposedToolNames = exposedToolNames
    }

    public mutating func registerTools(
        _ tools: [McpVisibleTool],
        bindingID: UInt64,
        appsEnabled: Bool,
        appsConfig: AppsConfig?,
        searchToolEnabled: Bool
    ) -> [McpToolRegistration] {
        if cached?.bindingID != bindingID {
            cached = CachedMcpHandlers(bindingID: bindingID)
        }
        var handlers = cached?.toolsByName ?? [:]
        let registrations = appendMcpTools(
            tools,
            appsEnabled: appsEnabled,
            appsConfig: appsConfig,
            searchToolEnabled: searchToolEnabled,
            handlers: &handlers
        )
        cached = CachedMcpHandlers(bindingID: bindingID, toolsByName: handlers)
        exposedToolNames = registrations
            .filter { $0.exposure != .hidden }
            .map(\.tool.name)
        return registrations
    }
}

public func toolIsModelVisible(_ tool: McpVisibleTool) -> Bool {
    guard let visibility = tool.visibility else { return true }
    return visibility.contains(mcpUIModelVisibility)
}

public func filterNonCodexAppsMcpToolsOnly(_ tools: [McpVisibleTool]) -> [McpVisibleTool] {
    tools.filter { tool in
        tool.resolvedServerName != CODEX_APPS_MCP_SERVER_NAME && toolIsModelVisible(tool)
    }
}

public func filterCodexAppsMcpTools(
    _ tools: [McpVisibleTool],
    appsConfig: AppsConfig?
) -> [McpVisibleTool] {
    let evaluator = AppToolPolicyEvaluator(appsConfig: appsConfig)
    return tools.filter { tool in
        guard tool.resolvedServerName == CODEX_APPS_MCP_SERVER_NAME else { return false }
        guard toolIsModelVisible(tool) else { return false }
        guard let connectorId = tool.connectorId else { return false }
        return evaluator.policy(
            AppToolPolicyInput(
                connectorId: connectorId,
                toolName: tool.name,
                toolTitle: tool.toolTitle,
                destructiveHint: tool.destructiveHint,
                openWorldHint: tool.openWorldHint
            )
        ).enabled
    }
}

public func appendMcpTools(
    _ tools: [McpVisibleTool],
    appsEnabled: Bool,
    appsConfig: AppsConfig?,
    searchToolEnabled: Bool,
    handlers: inout [String: McpVisibleTool]
) -> [McpToolRegistration] {
    let nonAppTools = filterNonCodexAppsMcpToolsOnly(tools)
    let appTools = appsEnabled ? filterCodexAppsMcpTools(tools, appsConfig: appsConfig) : []
    let baseExposure: McpToolExposure = searchToolEnabled ? .deferred : .direct
    var registrations: [McpToolRegistration] = []
    var agentPluginBytes = 0
    for tool in nonAppTools + appTools {
        let cached = handlers[tool.name] ?? tool
        handlers[tool.name] = cached
        let fitsAgentBudget: Bool
        if cached.isAgentPlugin {
            let bytes = cached.resolvedModelSpecBytes
            if bytes > maxAgentPluginMcpSpecBytes {
                fitsAgentBudget = false
            } else {
                let next = agentPluginBytes + bytes
                if next <= maxAgentPluginMcpTotalBytes {
                    agentPluginBytes = next
                    fitsAgentBudget = true
                } else {
                    fitsAgentBudget = false
                }
            }
        } else {
            fitsAgentBudget = true
        }
        registrations.append(
            McpToolRegistration(
                tool: cached,
                exposure: fitsAgentBudget ? baseExposure : .hidden
            )
        )
    }
    return registrations
}

public func appendMcpTools(
    _ tools: [McpVisibleTool],
    appsEnabled: Bool,
    appsConfig: AppsConfig?,
    searchToolEnabled: Bool
) -> [McpToolRegistration] {
    var handlers: [String: McpVisibleTool] = [:]
    return appendMcpTools(
        tools,
        appsEnabled: appsEnabled,
        appsConfig: appsConfig,
        searchToolEnabled: searchToolEnabled,
        handlers: &handlers
    )
}

func appIsEnabled(_ appsConfig: AppsConfig, connectorId: String?) -> Bool {
    let defaultEnabled = appsConfig.defaultEnabled ?? true
    guard let connectorId, let app = appsConfig.apps[connectorId] else {
        return defaultEnabled
    }
    return app.enabled
}

func appToolPolicy(from appsConfig: AppsConfig?, input: AppToolPolicyInput) -> AppToolPolicy {
    guard let appsConfig else {
        return AppToolPolicy()
    }
    let app = input.connectorId.flatMap { appsConfig.apps[$0] }
    let toolConfig = app.flatMap { app in
        app.tools[input.toolName] ?? input.toolTitle.flatMap { app.tools[$0] }
    }
    if !appIsEnabled(appsConfig, connectorId: input.connectorId) {
        return AppToolPolicy(enabled: false)
    }
    if let enabled = toolConfig?.enabled {
        return AppToolPolicy(enabled: enabled)
    }
    if let enabled = app?.defaultToolsEnabled {
        return AppToolPolicy(enabled: enabled)
    }
    let destructiveEnabled = app?.destructiveEnabled ?? true
    let openWorldEnabled = app?.openWorldEnabled ?? true
    let destructiveHint = input.destructiveHint ?? true
    let openWorldHint = input.openWorldHint ?? true
    let enabled = (destructiveEnabled || !destructiveHint) && (openWorldEnabled || !openWorldHint)
    return AppToolPolicy(enabled: enabled)
}
