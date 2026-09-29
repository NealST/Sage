//
//  list_available_plugins_to_install_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/list_available_plugins_to_install_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol

let LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME = "list_available_plugins_to_install"
let REQUEST_PLUGIN_INSTALL_TOOL_NAME = "request_plugin_install"

func createListAvailablePluginsToInstallTool() -> ToolSpec {
    let description = """
        # List plugin/connector install candidates

        Use this tool only when both are true:
        - The user explicitly asks to use a specific plugin or connector that is not already available in the current context or active `tools` list.
        - `\(TOOL_SEARCH_TOOL_NAME)` is not available, or it has already been called and did not find or make the requested tool callable.

        Returns known plugins and connectors that can be passed to `\(REQUEST_PLUGIN_INSTALL_TOOL_NAME)`. When both a plugin and a connector match, prefer the plugin; use the connector only when its corresponding plugin is already installed.

        """
    return .function(
        ResponsesApiTool(
            name: LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME,
            description: description,
            strict: false,
            parameters: .object([:], required: [], additionalProperties: false)
        )
    )
}
