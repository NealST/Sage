//
//  tool_spec.swift
//  Sage
//
//  Port of codex-rs/tools/src/tool_spec.rs + tool_executor.rs exposure
//  types used by core/src/tools (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol
import Foundation

struct ResponsesApiTool: Equatable, Sendable {
    var name: String
    var description: String
    var strict: Bool
    var parameters: JsonSchema
    var outputSchema: HarnessJSON?
}

struct ResponsesApiNamespaceTool: Equatable, Sendable {
    var function: ResponsesApiTool
}

struct ResponsesApiNamespace: Equatable, Sendable {
    var name: String
    var description: String
    var tools: [ResponsesApiNamespaceTool]
}

struct FreeformTool: Equatable, Sendable {
    var name: String
    var description: String
    var format: String
}

enum ToolSpec: Equatable, Sendable {
    case function(ResponsesApiTool)
    case namespace(ResponsesApiNamespace)
    case toolSearch(execution: String, description: String, parameters: JsonSchema)
    case webSearch(
        externalWebAccess: Bool?,
        indexedWebAccess: Bool?,
        filters: HarnessJSON?,
        userLocation: HarnessJSON?,
        searchContextSize: String?,
        searchContentTypes: [String]?
    )
    case freeform(FreeformTool)

    func name() -> String {
        switch self {
        case .function(let tool): return tool.name
        case .namespace(let namespace): return namespace.name
        case .toolSearch: return "tool_search"
        case .webSearch: return "web_search"
        case .freeform(let tool): return tool.name
        }
    }
}

enum ToolExposure: Equatable, Sendable {
    case direct
    case deferred
    case deferredModelOnly
    case directModelOnly
    case codeModeOnly
    case hidden

    func isDeferred() -> Bool {
        self == .deferred || self == .deferredModelOnly
    }
}

struct ToolSearchInfo: Equatable, Sendable {
    var description: String
    var keywords: [String]
    var source: ToolSearchSourceInfo?
}

struct ToolSearchSourceInfo: Equatable, Sendable {
    var name: String
    var description: String?
}
