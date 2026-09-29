//
//  service.swift
//  Sage
//
//  Port of codex-rs/core/src/state/service.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Phase 6/9 services (ModelClient, AuthManager, plugins) stay optional.
//  MCP catalog + handler cache names feed assembleToolRouter.
//  ExecutedToolCalls and unified exec are already in CodexCore / ToolsRuntimes.
//

import CodexCore
import CodexExecPolicy
import CodexProtocol
import Foundation

final class SessionServices: @unchecked Sendable {
    var mcpRuntime: SessionMcpRuntime
    var execPolicy: Policy?
    var showRawAgentReasoning: Bool
    var selectedCapabilityRoots: [String]
    var executedToolCalls: ExecutedToolCalls
    var modelClient: CodexCore.ModelClient?
    var availablePlugins: [PluginCapabilitySummary]
    var availableConnectors: [AppInfo]
    var mcpTools: [PluginToolInfo]
    var modelVisibleMcpToolNames: [String]
    var mcpVisibleTools: [McpVisibleTool]
    var mcpHandlerCache: McpHandlerCache
    var skillsLookup: SessionSkillsLookup
    var turnInputContributors: [any TurnInputContributor]

    init(
        mcpRuntime: SessionMcpRuntime = SessionMcpRuntime(),
        execPolicy: Policy? = nil,
        showRawAgentReasoning: Bool = false,
        selectedCapabilityRoots: [String] = [],
        modelClient: CodexCore.ModelClient? = nil,
        availablePlugins: [PluginCapabilitySummary] = [],
        availableConnectors: [AppInfo] = [],
        mcpTools: [PluginToolInfo] = [],
        modelVisibleMcpToolNames: [String] = [],
        mcpVisibleTools: [McpVisibleTool] = [],
        mcpHandlerCache: McpHandlerCache = McpHandlerCache(),
        skillsLookup: SessionSkillsLookup = SessionSkillsLookup(),
        turnInputContributors: [any TurnInputContributor] = []
    ) {
        self.mcpRuntime = mcpRuntime
        self.execPolicy = execPolicy
        self.showRawAgentReasoning = showRawAgentReasoning
        self.selectedCapabilityRoots = selectedCapabilityRoots
        self.executedToolCalls = ExecutedToolCalls()
        self.modelClient = modelClient
        self.availablePlugins = availablePlugins
        self.availableConnectors = availableConnectors
        self.mcpTools = mcpTools
        self.modelVisibleMcpToolNames = modelVisibleMcpToolNames
        self.mcpVisibleTools = mcpVisibleTools
        self.mcpHandlerCache = mcpHandlerCache
        self.skillsLookup = skillsLookup
        self.turnInputContributors = turnInputContributors
    }
}

protocol TurnInputContributor: AnyObject {
    func contribute(userInput: [UserInput], turnId: String) async -> [ResponseItem]
}
