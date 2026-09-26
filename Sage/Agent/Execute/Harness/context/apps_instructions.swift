//
//  apps_instructions.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/apps_instructions.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct AppsInstructions: ContextualUserFragment, Equatable, Sendable {
    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("apps.instructions") }
    public var role: String { "developer" }
    public var openMarker: String { appsInstructionsOpenTag }
    public var closeMarker: String { appsInstructionsCloseTag }
    public var body: String {
        """

        ## Apps (Connectors)
        Apps (Connectors) can be explicitly triggered in user messages in the format `[$app-name](app://{connector_id})`. Apps can also be implicitly triggered as long as the context suggests usage of available apps.
        An app is equivalent to a set of MCP tools within the `codex_apps` MCP.
        An installed app's MCP tools are either provided to you already, or can be lazy-loaded through the `tool_search` tool. If `tool_search` is available, the apps that are searchable by `tools_search` will be listed by it.
        Do not additionally call list_mcp_resources or list_mcp_resource_templates for apps.
        """
    }
}
