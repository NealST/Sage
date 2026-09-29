//
//  request_plugin_install_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/request_plugin_install_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  ToolSuggestPresentation is a local stand-in until the router is ported.
//

import CodexProtocol

enum ToolSuggestPresentation: Equatable, Sendable {
    case listTool
    case recommendationContext
}

func createRequestPluginInstallTool(_ presentation: ToolSuggestPresentation) -> ToolSpec {
    let properties: [String: JsonSchema]
    let required: [String]
    let description: String
    switch presentation {
    case .listTool:
        properties = [
            "tool_type": .string("Type of discoverable tool to suggest. Use \"connector\" or \"plugin\"."),
            "action_type": .string("Suggested action for the tool. Use \"install\"."),
            "tool_id": .string("Connector or plugin id to suggest."),
            "suggest_reason": .string(
                "Concise one-line user-facing reason why this plugin or connector can help with the current request."
            ),
        ]
        required = ["tool_type", "action_type", "tool_id", "suggest_reason"]
        description = """
            # Request plugin/connector install

            Use this tool only after `\(LIST_AVAILABLE_PLUGINS_TO_INSTALL_TOOL_NAME)` returns a plugin or connector that exactly matches the user's explicit request.

            Do not use it for adjacent capabilities, broad recommendations, or tools that merely seem useful. Pass the returned `tool_type` through directly, and pass the returned `id` as `tool_id`.

            IMPORTANT: DO NOT call this tool in parallel with other tools.
            """
    case .recommendationContext:
        properties = [
            "plugin_id": .string("The parenthesized plugin ID from the `<recommended_plugins>` list."),
            "suggest_reason": .string(
                "Concise one-line user-facing reason why this plugin can help with the current request."
            ),
        ]
        required = ["plugin_id", "suggest_reason"]
        description = """
            # Suggest a recommended plugin installation

            Use this tool only when all of the following are true:
            - The user explicitly asks to use a specific plugin that is not already available in the current context or active `tools` list.
            - Tool search has already been exhausted and did not find or make the requested tool callable.
            - The plugin is listed in `<recommended_plugins>`.

            Do not use it for adjacent capabilities, broad recommendations, or plugins that merely seem useful. Briefly explain why the plugin can help with the current request in `suggest_reason`.

            IMPORTANT: DO NOT call this tool in parallel with other tools.
            """
    }
    return .function(
        ResponsesApiTool(
            name: REQUEST_PLUGIN_INSTALL_TOOL_NAME,
            description: description,
            strict: false,
            parameters: .object(properties, required: required, additionalProperties: false)
        )
    )
}
