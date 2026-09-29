//
//  request_plugin_install.swift
//  Sage
//
//  Port of
//  codex-rs/core/src/tools/handlers/request_plugin_install.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Argument parsing, root-thread check, and candidate matching are live.
//  Install elicitation waits on Session / PluginsManager.
//

import CodexCore
import CodexProtocol

let REQUEST_PLUGIN_INSTALL_APPROVAL_KIND_VALUE = "tool_suggestion"
let REQUEST_PLUGIN_INSTALL_PERSIST_KEY = "persist"
let REQUEST_PLUGIN_INSTALL_PERSIST_ALWAYS_VALUE = "always"

struct RequestPluginInstallArgs: Decodable, Equatable, Sendable {
    var toolType: DiscoverableToolType
    var actionType: DiscoverableToolAction
    var toolId: String
    var suggestReason: String

    enum CodingKeys: String, CodingKey {
        case toolType = "tool_type"
        case actionType = "action_type"
        case toolId = "tool_id"
        case suggestReason = "suggest_reason"
    }
}

struct RecommendedPluginInstallArgs: Decodable, Equatable, Sendable {
    var pluginId: String
    var suggestReason: String

    enum CodingKeys: String, CodingKey {
        case pluginId = "plugin_id"
        case toolId = "tool_id"
        case suggestReason = "suggest_reason"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginId = try container.decodeIfPresent(String.self, forKey: .pluginId)
            ?? container.decode(String.self, forKey: .toolId)
        suggestReason = try container.decode(String.self, forKey: .suggestReason)
    }
}

struct RequestPluginInstallResult: Encodable, Equatable, Sendable, ToolOutput {
    var completed: Bool
    var userConfirmed: Bool
    var toolType: DiscoverableToolType
    var actionType: DiscoverableToolAction
    var toolId: String
    var toolName: String
    var suggestReason: String

    enum CodingKeys: String, CodingKey {
        case completed
        case userConfirmed = "user_confirmed"
        case toolType = "tool_type"
        case actionType = "action_type"
        case toolId = "tool_id"
        case toolName = "tool_name"
        case suggestReason = "suggest_reason"
    }

    func logOutput() -> String { toolOutputJsonText(self, toolName: REQUEST_PLUGIN_INSTALL_TOOL_NAME) }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId,
            payload: payload,
            value: self,
            success: true,
            toolName: REQUEST_PLUGIN_INSTALL_TOOL_NAME
        )
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: REQUEST_PLUGIN_INSTALL_TOOL_NAME)
    }
}

func parseRequestPluginInstallSelection(
    arguments: String,
    presentation: ToolSuggestPresentation
) throws -> (toolId: String, toolType: DiscoverableToolType?, suggestReason: String) {
    switch presentation {
    case .listTool:
        let args: RequestPluginInstallArgs = try parseArguments(arguments)
        if args.actionType != .install {
            throw FunctionCallError.respondToModel(
                "plugin install requests currently support only action_type=\"install\""
            )
        }
        return (args.toolId, args.toolType, args.suggestReason)
    case .recommendationContext:
        let args: RecommendedPluginInstallArgs = try parseArguments(arguments)
        return (args.pluginId, nil, args.suggestReason)
    }
}

func matchRequestPluginInstallTool(
    requestedToolId: String,
    requestedToolType: DiscoverableToolType?,
    presentation: ToolSuggestPresentation,
    discoverableTools: [DiscoverableTool],
    appServerClientName: String?
) throws -> DiscoverableTool {
    let discoverableTools = filterRequestPluginInstallDiscoverableToolsForClient(
        discoverableTools,
        appServerClientName: appServerClientName
    )
    if let tool = discoverableTools.first(where: { tool in
        tool.id() == requestedToolId
            && {
                switch presentation {
                case .listTool:
                    return requestedToolType.map { $0 == tool.toolType() } ?? false
                case .recommendationContext:
                    if case .plugin = tool { return true }
                    return false
                }
            }()
    }) {
        return tool
    }
    let (argumentName, source) = switch presentation {
    case .listTool:
        (
            "tool_id",
            "the discoverable tools returned by \(LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME)"
        )
    case .recommendationContext:
        ("plugin_id", "the entries in the <recommended_plugins> list")
    }
    throw FunctionCallError.respondToModel("\(argumentName) must match one of \(source)")
}

func allRequestedConnectorsPickedUp(
    expectedConnectorIds: [String],
    accessibleConnectors: [AppInfo]
) -> Bool {
    expectedConnectorIds.allSatisfy { connectorId in
        verifiedConnectorInstallCompleted(connectorId, accessibleConnectors: accessibleConnectors)
    }
}

func verifiedConnectorInstallCompleted(
    _ toolId: String,
    accessibleConnectors: [AppInfo]
) -> Bool {
    accessibleConnectors.first { $0.id == toolId }?.isAccessible == true
}

func buildRequestPluginInstallElicitationRequest(
    suggestReason: String,
    tool: DiscoverableTool,
    suggestionId: String
) -> ElicitationRequest {
    _ = tool
    _ = suggestionId
    return .form(
        meta: nil,
        message: suggestReason,
        requestedSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )
}

struct RequestPluginInstallHandler: CoreToolRuntime {
    var discoverableTools: [DiscoverableTool]
    var presentation: ToolSuggestPresentation

    init(
        discoverableTools: [DiscoverableTool] = [],
        presentation: ToolSuggestPresentation = .listTool
    ) {
        self.discoverableTools = discoverableTools
        self.presentation = presentation
    }

    func toolName() -> ToolName { ToolName(plain: REQUEST_PLUGIN_INSTALL_TOOL_NAME) }
    func spec() -> ToolSpec { createRequestPluginInstallTool(presentation) }
    func supportsParallelToolCalls() -> Bool { false }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        if !invocation.isRootThread {
            throw FunctionCallError.respondToModel(
                "request_plugin_install can only be used by the root thread"
            )
        }
        let (requestedToolId, requestedToolType, suggestReason) =
            try parseRequestPluginInstallSelection(
                arguments: arguments,
                presentation: presentation
            )
        let suggestReason = suggestReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if suggestReason.isEmpty {
            throw FunctionCallError.respondToModel("suggest_reason must not be empty")
        }
        _ = try matchRequestPluginInstallTool(
            requestedToolId: requestedToolId,
            requestedToolType: requestedToolType,
            presentation: presentation,
            discoverableTools: discoverableTools,
            appServerClientName: nil
        )
        throw FunctionCallError.respondToModel(
            "request_plugin_install waits on Session / PluginsManager"
        )
    }
}
