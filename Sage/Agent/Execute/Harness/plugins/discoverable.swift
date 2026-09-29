//
//  discoverable.swift
//  CodexCore
//
//  Port of codex-rs/core/src/plugins/discoverable.rs and
//  codex-rs/tools/src/tool_discovery.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Discoverable tool types and client filtering are faithful. Plugin
//  listing still waits on Config / PluginsManager / CodexAuth.
//

import CodexProtocol
import Foundation

public let TUI_CLIENT_NAME = "codex-tui"

public enum DiscoverableToolType: String, Codable, Equatable, Sendable {
    case connector
    case plugin
}

public enum DiscoverableToolAction: String, Codable, Equatable, Sendable {
    case install
    case enable
}

public struct DiscoverablePluginInfo: Equatable, Sendable {
    public var id: String
    public var remotePluginId: String?
    public var name: String
    public var description: String?
    public var hasSkills: Bool
    public var mcpServerNames: [String]
    public var appConnectorIds: [String]

    public init(
        id: String,
        remotePluginId: String? = nil,
        name: String,
        description: String? = nil,
        hasSkills: Bool = false,
        mcpServerNames: [String] = [],
        appConnectorIds: [String] = []
    ) {
        self.id = id
        self.remotePluginId = remotePluginId
        self.name = name
        self.description = description
        self.hasSkills = hasSkills
        self.mcpServerNames = mcpServerNames
        self.appConnectorIds = appConnectorIds
    }
}

public enum DiscoverableTool: Equatable, Sendable {
    case connector(AppInfo)
    case plugin(DiscoverablePluginInfo)

    public func toolType() -> DiscoverableToolType {
        switch self {
        case .connector: return .connector
        case .plugin: return .plugin
        }
    }

    public func id() -> String {
        switch self {
        case .connector(let connector): return connector.id
        case .plugin(let plugin): return plugin.id
        }
    }

    public func name() -> String {
        switch self {
        case .connector(let connector): return connector.name
        case .plugin(let plugin): return plugin.name
        }
    }

    public func installUrl() -> String? {
        switch self {
        case .connector(let connector): return connector.installUrl
        case .plugin: return nil
        }
    }
}

public struct RequestPluginInstallEntry: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var toolType: DiscoverableToolType
    public var hasSkills: Bool
    public var mcpServerNames: [String]
    public var appConnectorIds: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case toolType = "tool_type"
        case hasSkills = "has_skills"
        case mcpServerNames = "mcp_server_names"
        case appConnectorIds = "app_connector_ids"
    }

    public init(
        id: String,
        name: String,
        description: String? = nil,
        toolType: DiscoverableToolType,
        hasSkills: Bool = false,
        mcpServerNames: [String] = [],
        appConnectorIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.toolType = toolType
        self.hasSkills = hasSkills
        self.mcpServerNames = mcpServerNames
        self.appConnectorIds = appConnectorIds
    }
}

public func filterRequestPluginInstallDiscoverableToolsForClient(
    _ discoverableTools: [DiscoverableTool],
    appServerClientName: String?
) -> [DiscoverableTool] {
    if appServerClientName != TUI_CLIENT_NAME {
        return discoverableTools
    }
    return discoverableTools.filter { tool in
        if case .plugin = tool { return false }
        return true
    }
}

public let MAX_LIST_AVAILABLE_PLUGINS_TO_INSTALL_DESCRIPTION_CHARS = 240

public struct ListAvailablePluginsToInstallResult: Codable, Equatable, Sendable {
    public var tools: [RequestPluginInstallEntry]

    public init(tools: [RequestPluginInstallEntry]) {
        self.tools = tools
    }
}

public func truncateToCharBoundary(_ value: String, maxChars: Int) -> String {
    guard value.count > maxChars else { return value }
    return String(value.prefix(maxChars))
}

public func listAvailablePluginsToInstallResult(
    _ tools: [RequestPluginInstallEntry]
) -> ListAvailablePluginsToInstallResult {
    let tools = tools
        .sorted { left, right in
            if left.name != right.name { return left.name < right.name }
            return left.id < right.id
        }
        .map { tool in
            var tool = tool
            tool.description = tool.description.map {
                truncateToCharBoundary($0, maxChars: MAX_LIST_AVAILABLE_PLUGINS_TO_INSTALL_DESCRIPTION_CHARS)
            }
            return tool
        }
    return ListAvailablePluginsToInstallResult(tools: tools)
}

public func collectRequestPluginInstallEntries(
    _ discoverableTools: [DiscoverableTool]
) -> [RequestPluginInstallEntry] {
    discoverableTools.map { tool in
        switch tool {
        case .connector(let connector):
            return RequestPluginInstallEntry(
                id: connector.id,
                name: connector.name,
                description: connector.description,
                toolType: .connector
            )
        case .plugin(let plugin):
            return RequestPluginInstallEntry(
                id: plugin.id,
                name: plugin.name,
                description: plugin.description,
                toolType: .plugin,
                hasSkills: plugin.hasSkills,
                mcpServerNames: plugin.mcpServerNames,
                appConnectorIds: plugin.appConnectorIds
            )
        }
    }
}

public func listToolSuggestDiscoverablePlugins() async throws -> Never {
    throw CodexErr.unsupportedOperation(
        "list_tool_suggest_discoverable_plugins waits on Config / PluginsManager / CodexAuth"
    )
}
