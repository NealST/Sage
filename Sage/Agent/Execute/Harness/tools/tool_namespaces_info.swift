//
//  tool_namespaces_info.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/tool_namespaces_info.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  TurnToolNamespacesInfo lives in responses_metadata (Phase 6). This
//  file keeps a local snapshot used by ToolRouter.
//

import CodexProtocol

let TOOL_SEARCH_TOOL_NAME = "tool_search"
let TOOL_SEARCH_FUNCTION_NAME = "tool_search_tool"

enum TurnToolSource: Equatable, Sendable {
    case harness
    case mcp(serverName: String)
}

struct TurnToolFunctionInfo: Equatable, Sendable {
    var name: String
    var direct: Bool
    var deferred: Bool
    var source: TurnToolSource
}

struct TurnToolNamespaceInfo: Equatable, Sendable {
    var name: String
    var functions: [String: TurnToolFunctionInfo]
}

func collectToolNamespacesInfo(
    registry: HarnessToolRegistry,
    modelVisibleSpecs: [ToolSpec]
) -> [String: TurnToolNamespaceInfo] {
    var directFunctions = Set<String>()
    var nativeToolSearchVisible = false
    for spec in modelVisibleSpecs {
        switch spec {
        case .function(let tool):
            directFunctions.insert("\(DEFAULT_FUNCTION_NAMESPACE).\(tool.name)")
        case .namespace(let namespace):
            for tool in namespace.tools {
                directFunctions.insert("\(namespace.name).\(tool.function.name)")
            }
        case .toolSearch:
            nativeToolSearchVisible = true
            directFunctions.insert("\(TOOL_SEARCH_TOOL_NAME).\(TOOL_SEARCH_FUNCTION_NAME)")
        case .webSearch, .freeform:
            break
        }
    }

    var namespaces: [String: TurnToolNamespaceInfo] = [:]
    for entry in registry.registeredEntries() {
        if entry.exposure == .hidden { continue }
        let toolName = entry.runtime.toolName().withDefaultNamespace()
        let namespaceName = toolName.namespace ?? DEFAULT_FUNCTION_NAMESPACE
        let functionName = toolName.name
        let direct = directFunctions.contains("\(namespaceName).\(functionName)")
        let deferred = entry.exposure.isDeferred() && nativeToolSearchVisible
        if !direct && !deferred { continue }
        var namespace = namespaces[namespaceName] ?? TurnToolNamespaceInfo(name: namespaceName, functions: [:])
        namespace.functions[functionName] = TurnToolFunctionInfo(
            name: functionName,
            direct: direct,
            deferred: deferred,
            source: entry.runtime.mcpServerName().map { .mcp(serverName: $0) } ?? .harness
        )
        namespaces[namespaceName] = namespace
    }
    return namespaces
}
