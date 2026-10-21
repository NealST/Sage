//
//  tool_spec.swift
//  Sage
//
//  Port of codex-rs/tools/src/tool_spec.rs + tool_executor.rs exposure
//  types used by core/src/tools (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import SageProtocol
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

    /// rust `serde_json::to_value(&ToolSpec)` — a valid Responses API
    /// tool. Sage's `builtTools` renders model-visible specs through this
    /// instead of a parallel responses-tools array.
    func toJSON() -> SageProtocol.JSONValue {
        switch self {
        case .function(let tool):
            return .object([
                "type": .string("function"),
                "name": .string(tool.name),
                "description": .string(tool.description),
                "strict": .bool(tool.strict),
                "parameters": tool.parameters.toJSON(),
            ])
        case .namespace(let namespace):
            return .object([
                "type": .string("namespace"),
                "name": .string(namespace.name),
                "description": .string(namespace.description),
                "tools": .array(namespace.tools.map { namespaced in
                    .object([
                        "type": .string("function"),
                        "name": .string(namespaced.function.name),
                        "description": .string(namespaced.function.description),
                        "strict": .bool(namespaced.function.strict),
                        "parameters": namespaced.function.parameters.toJSON(),
                    ])
                }),
            ])
        case .toolSearch(let execution, let description, let parameters):
            return .object([
                "type": .string("tool_search"),
                "execution": .string(execution),
                "description": .string(description),
                "parameters": parameters.toJSON(),
            ])
        case .webSearch(
            let externalWebAccess,
            let indexedWebAccess,
            let filters,
            let userLocation,
            let searchContextSize,
            let searchContentTypes
        ):
            var fields: [String: SageProtocol.JSONValue] = ["type": .string("web_search")]
            if let externalWebAccess {
                fields["external_web_access"] = .bool(externalWebAccess)
            }
            if let indexedWebAccess {
                fields["indexed_web_access"] = .bool(indexedWebAccess)
            }
            if let filters {
                fields["filters"] = filters
            }
            if let userLocation {
                fields["user_location"] = userLocation
            }
            if let searchContextSize {
                fields["search_context_size"] = .string(searchContextSize)
            }
            if let searchContentTypes {
                fields["search_content_types"] = .array(searchContentTypes.map { .string($0) })
            }
            return .object(fields)
        case .freeform(let tool):
            return .object([
                "type": .string("custom"),
                "name": .string(tool.name),
                "description": .string(tool.description),
                "format": .string(tool.format),
            ])
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

    func isDirect() -> Bool {
        self == .direct || self == .directModelOnly
    }

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
