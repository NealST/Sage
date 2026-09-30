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
    public var connectorId: String?
    public var toolTitle: String?
    public var visibility: [String]?
    public var destructiveHint: Bool?
    public var openWorldHint: Bool?
    public var isAgentPlugin: Bool
    public var modelSpecBytes: Int?
    public var namespaceDescription: String?

    public init(
        name: String,
        description: String = "",
        serverName: String? = nil,
        parametersJSON: String? = nil,
        connectorId: String? = nil,
        toolTitle: String? = nil,
        visibility: [String]? = nil,
        destructiveHint: Bool? = nil,
        openWorldHint: Bool? = nil,
        isAgentPlugin: Bool = false,
        modelSpecBytes: Int? = nil,
        namespaceDescription: String? = nil
    ) {
        self.name = name
        self.description = description
        self.serverName = serverName
        self.parametersJSON = parametersJSON
        self.connectorId = connectorId
        self.toolTitle = toolTitle
        self.visibility = visibility
        self.destructiveHint = destructiveHint
        self.openWorldHint = openWorldHint
        self.isAgentPlugin = isAgentPlugin
        self.modelSpecBytes = modelSpecBytes
        self.namespaceDescription = namespaceDescription
    }

    public var resolvedServerName: String {
        serverName ?? ""
    }

    public var resolvedModelSpecBytes: Int {
        if let modelSpecBytes { return modelSpecBytes }
        return name.utf8.count
            + description.utf8.count
            + (parametersJSON?.utf8.count ?? 0)
            + (namespaceDescription?.utf8.count ?? 0)
    }
}

public func pluginsManagerForConfig() throws -> Never {
    throw CodexErr.unsupportedOperation(
        "plugins_manager_for_config waits on Config / AuthManager / HostSkillsService"
    )
}
