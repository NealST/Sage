//
//  mcp_resource_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/mcp_resource_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol

func createListMcpResourcesTool(description: String? = nil, parameters: String? = nil) -> ToolSpec {
    withModelMessages(
        ResponsesApiTool(
            name: "list_mcp_resources",
            description: description ?? "Lists resources provided by MCP servers. Resources allow servers to share data that provides context to language models, such as files, database schemas, or application-specific information. Prefer resources over web search when possible.",
            strict: false,
            parameters: applyCatalogParameters(
                .object(
                    [
                        "server": .string(
                            "MCP server name. Omit to list resources from every configured server."
                        ),
                        "cursor": .string(
                            "Opaque cursor from a previous list_mcp_resources call; omit for the first page."
                        ),
                    ],
                    additionalProperties: false
                ),
                parameters
            )
        )
    )
}

func createListMcpResourceTemplatesTool(description: String? = nil, parameters: String? = nil) -> ToolSpec {
    withModelMessages(
        ResponsesApiTool(
            name: "list_mcp_resource_templates",
            description: description ?? "Lists resource templates provided by MCP servers. Parameterized resource templates allow servers to share data that takes parameters and provides context to language models, such as files, database schemas, or application-specific information. Prefer resource templates over web search when possible.",
            strict: false,
            parameters: applyCatalogParameters(
                .object(
                    [
                        "server": .string(
                            "MCP server name. Omit to list resource templates from every configured server."
                        ),
                        "cursor": .string(
                            "Opaque cursor from a previous list_mcp_resource_templates call; omit for the first page."
                        ),
                    ],
                    additionalProperties: false
                ),
                parameters
            )
        )
    )
}

func createReadMcpResourceTool(description: String? = nil, parameters: String? = nil) -> ToolSpec {
    withModelMessages(
        ResponsesApiTool(
            name: "read_mcp_resource",
            description: description ?? "Read a specific resource from an MCP server given the server name and resource URI.",
            strict: false,
            parameters: applyCatalogParameters(
                .object(
                    [
                        "server": .string(
                            "MCP server name exactly as configured. Must match the 'server' field returned by list_mcp_resources."
                        ),
                        "uri": .string(
                            "Resource URI to read. Must be one of the URIs returned by list_mcp_resources."
                        ),
                    ],
                    required: ["server", "uri"],
                    additionalProperties: false
                ),
                parameters
            )
        )
    )
}

func withModelMessages(_ tool: ResponsesApiTool) -> ToolSpec {
    .function(tool)
}

func applyCatalogParameters(_ fallback: JsonSchema, _ override: String?) -> JsonSchema {
    guard let override else { return fallback }
    return (try? parseCatalogParameters(override)) ?? fallback
}
