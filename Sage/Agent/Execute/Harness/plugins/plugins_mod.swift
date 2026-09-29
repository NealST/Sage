//
//  plugins_mod.swift
//  CodexCore
//
//  Port of codex-rs/core/src/plugins/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename `mod.swift` is taken by `unified_exec/mod.swift`.
//  `PluginCapabilitySummary` is inlined from the plugin crate. The
//  PluginsManager constructor waits on Config / AuthManager / HostSkillsService.
//

import CodexProtocol
import Foundation

public struct PluginCapabilitySummary: Equatable, Sendable {
    public var configName: String
    public var displayName: String
    public var pluginNamespace: String?
    public var description: String?
    public var hasSkills: Bool
    public var mcpServerNames: [String]
    public var appConnectorIds: [String]

    public init(
        configName: String,
        displayName: String,
        pluginNamespace: String? = nil,
        description: String? = nil,
        hasSkills: Bool = false,
        mcpServerNames: [String] = [],
        appConnectorIds: [String] = []
    ) {
        self.configName = configName
        self.displayName = displayName
        self.pluginNamespace = pluginNamespace
        self.description = description
        self.hasSkills = hasSkills
        self.mcpServerNames = mcpServerNames
        self.appConnectorIds = appConnectorIds
    }
}

public struct PluginToolInfo: Equatable, Sendable {
    public var serverName: String
    public var pluginDisplayNames: [String]

    public init(serverName: String, pluginDisplayNames: [String] = []) {
        self.serverName = serverName
        self.pluginDisplayNames = pluginDisplayNames
    }
}

public struct McpVisibleTool: Equatable, Sendable {
    public var name: String
    public var description: String
    public var serverName: String?
    public var parametersJSON: String?

    public init(
        name: String,
        description: String = "",
        serverName: String? = nil,
        parametersJSON: String? = nil
    ) {
        self.name = name
        self.description = description
        self.serverName = serverName
        self.parametersJSON = parametersJSON
    }
}

public func pluginsManagerForConfig() throws -> Never {
    throw CodexErr.unsupportedOperation(
        "plugins_manager_for_config waits on Config / AuthManager / HostSkillsService"
    )
}
