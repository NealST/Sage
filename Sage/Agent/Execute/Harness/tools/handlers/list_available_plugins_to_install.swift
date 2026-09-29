//
//  list_available_plugins_to_install.swift
//  Sage
//
//  Port of
//  codex-rs/core/src/tools/handlers/list_available_plugins_to_install.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Sorting, truncation, and JSON output are faithful. Candidate discovery
//  still waits on PluginsManager / Config.
//

import CodexCore
import CodexProtocol

struct ListAvailablePluginsToInstallToolOutput: Encodable, Equatable, Sendable, ToolOutput {
    var tools: [RequestPluginInstallEntry]

    init(_ result: ListAvailablePluginsToInstallResult) {
        self.tools = result.tools
    }

    func logOutput() -> String {
        toolOutputJsonText(self, toolName: LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME)
    }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId,
            payload: payload,
            value: self,
            success: true,
            toolName: LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME
        )
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME)
    }
}

struct ListAvailablePluginsToInstallHandler: CoreToolRuntime {
    var tools: [RequestPluginInstallEntry]

    init(tools: [RequestPluginInstallEntry] = []) {
        self.tools = tools
    }

    func toolName() -> ToolName { ToolName(plain: LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME) }
    func spec() -> ToolSpec { createListAvailablePluginsToInstallTool() }
    func supportsParallelToolCalls() -> Bool { false }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function = invocation.payload else {
            throw FunctionCallError.fatal(
                "\(LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME) handler received unsupported payload"
            )
        }
        return boxedToolOutput(
            ListAvailablePluginsToInstallToolOutput(listAvailablePluginsToInstallResult(tools))
        )
    }
}
