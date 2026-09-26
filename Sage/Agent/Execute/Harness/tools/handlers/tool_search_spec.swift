//
//  tool_search_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/tool_search_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexUtils

let MAX_TOOL_SEARCH_SOURCE_DESCRIPTION_BYTES = 512 * 1024

enum ToolSearchSourceListing: Equatable, Sendable {
    case include
    case omit
}

func createToolSearchTool(
    searchableSources: [ToolSearchSourceInfo],
    defaultLimit: Int,
    sourceListing: ToolSearchSourceListing
) -> ToolSpec {
    let properties: [String: JsonSchema] = [
        "query": .string("Search query for deferred tools."),
        "limit": .number("Maximum number of tools to return. Defaults to \(defaultLimit)."),
    ]
    let sourceSection: String
    switch sourceListing {
    case .include:
        var sourceDescriptions: [String: String?] = [:]
        var order: [String] = []
        for source in searchableSources {
            if sourceDescriptions[source.name] == nil {
                order.append(source.name)
                sourceDescriptions[source.name] = source.description
            } else if sourceDescriptions[source.name] == nil {
                sourceDescriptions[source.name] = source.description
            } else if sourceDescriptions[source.name] == Optional<String>.none {
                sourceDescriptions[source.name] = source.description
            }
        }
        let rendered: String
        if order.isEmpty {
            rendered = "None currently enabled."
        } else {
            let reservedNameBytes = order.reduce(order.count.saturatingSubtract(1)) { reserved, name in
                reserved.saturatingAdd(2).saturatingAdd(name.utf8.count)
            }
            var descriptionBudget = MAX_TOOL_SEARCH_SOURCE_DESCRIPTION_BYTES.saturatingSubtract(reservedNameBytes)
            var text = ""
            for name in order {
                let separatorBytes = text.isEmpty ? 0 : 1
                let required = separatorBytes.saturatingAdd(2).saturatingAdd(name.utf8.count)
                if required > MAX_TOOL_SEARCH_SOURCE_DESCRIPTION_BYTES.saturatingSubtract(text.utf8.count) {
                    continue
                }
                if !text.isEmpty { text.append("\n") }
                text.append("- ")
                text.append(name)
                if let description = sourceDescriptions[name] ?? nil, descriptionBudget >= 2 {
                    text.append(": ")
                    descriptionBudget -= 2
                    let bounded = takeBytesAtCharBoundary(description, maxb: descriptionBudget)
                    text.append(contentsOf: bounded)
                    descriptionBudget -= bounded.utf8.count
                }
            }
            rendered = text
        }
        sourceSection = "\n\nYou have access to tools from the following sources:\n\(rendered)\n"
    case .omit:
        sourceSection = "\n\n"
    }
    let description = "# Tool discovery\n\nSearches over deferred tool metadata with BM25 and exposes matching tools for the next model call.\(sourceSection)Some of the tools may not have been provided to you upfront, and you should use this tool (`\(TOOL_SEARCH_TOOL_NAME)`) to search for the required tools. For MCP tool discovery, always use `\(TOOL_SEARCH_TOOL_NAME)` instead of `list_mcp_resources` or `list_mcp_resource_templates`."
    return .toolSearch(
        execution: "client",
        description: description,
        parameters: .object(properties, required: ["query"], additionalProperties: false)
    )
}

private extension Int {
    func saturatingSubtract(_ other: Int) -> Int { Swift.max(0, self - other) }
    func saturatingAdd(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? Int.max : result
    }
}
