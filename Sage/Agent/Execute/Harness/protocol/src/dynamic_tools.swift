//
//  dynamic_tools.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/dynamic_tools.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Dynamic tool specification types and legacy-format normalization.
//

import Foundation

// MARK: - DynamicToolSpec

public enum DynamicToolSpec: Codable, Equatable, Sendable {
    case function(DynamicToolFunctionSpec)
    case namespace(DynamicToolNamespaceSpec)

    private enum TypeKey: String, CodingKey { case type_ = "type" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "function":
            self = .function(try DynamicToolFunctionSpec(from: decoder))
        case "namespace":
            self = .namespace(try DynamicToolNamespaceSpec(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown DynamicToolSpec type: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .function(let spec):
            try container.encode("function", forKey: .type_)
            try spec.encode(to: encoder)
        case .namespace(let spec):
            try container.encode("namespace", forKey: .type_)
            try spec.encode(to: encoder)
        }
    }
}

// MARK: - DynamicToolFunctionSpec

public struct DynamicToolFunctionSpec: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
    public var deferLoading: Bool

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "inputSchema"
        case deferLoading = "deferLoading"
    }

    public init(
        name: String, description: String, inputSchema: JSONValue, deferLoading: Bool = false
    ) {
        self.name = name; self.description = description
        self.inputSchema = inputSchema; self.deferLoading = deferLoading
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        inputSchema = try container.decode(JSONValue.self, forKey: .inputSchema)
        deferLoading = try container.decodeIfPresent(Bool.self, forKey: .deferLoading) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
        if deferLoading {
            try container.encode(deferLoading, forKey: .deferLoading)
        }
    }
}

// MARK: - DynamicToolNamespaceSpec

public struct DynamicToolNamespaceSpec: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var tools: [DynamicToolNamespaceTool]

    public init(name: String, description: String = "", tools: [DynamicToolNamespaceTool] = []) {
        self.name = name; self.description = description; self.tools = tools
    }
}

// MARK: - DynamicToolNamespaceTool

public enum DynamicToolNamespaceTool: Codable, Equatable, Sendable {
    case function(DynamicToolFunctionSpec)

    private enum TypeKey: String, CodingKey { case type_ = "type" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        switch type_ {
        case "function":
            self = .function(try DynamicToolFunctionSpec(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown DynamicToolNamespaceTool type: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .function(let spec):
            try container.encode("function", forKey: .type_)
            try spec.encode(to: encoder)
        }
    }
}

// MARK: - DynamicToolCallRequest

public struct DynamicToolCallRequest: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String
    public var startedAtMs: Int64
    public var namespace: String?
    public var tool: String
    public var arguments: JSONValue

    public init(
        callId: String,
        turnId: String,
        startedAtMs: Int64 = 0,
        namespace: String? = nil,
        tool: String,
        arguments: JSONValue
    ) {
        self.callId = callId
        self.turnId = turnId
        self.startedAtMs = startedAtMs
        self.namespace = namespace
        self.tool = tool
        self.arguments = arguments
    }

    enum CodingKeys: String, CodingKey {
        case callId = "callId"
        case turnId = "turnId"
        case startedAtMs = "startedAtMs"
        case namespace, tool, arguments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        turnId = try container.decode(String.self, forKey: .turnId)
        startedAtMs = try container.decodeIfPresent(Int64.self, forKey: .startedAtMs) ?? 0
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        tool = try container.decode(String.self, forKey: .tool)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
    }
}

// MARK: - DynamicToolResponse

public struct DynamicToolResponse: Codable, Equatable, Sendable {
    public var contentItems: [DynamicToolCallOutputContentItem]
    public var success: Bool

    enum CodingKeys: String, CodingKey {
        case contentItems = "contentItems"
        case success
    }
}

// MARK: - DynamicToolCallOutputContentItem

public enum DynamicToolCallOutputContentItem: Codable, Equatable, Sendable {
    case inputText(text: String)
    case inputImage(imageUrl: String)
    case inputAudio(audioUrl: String)

    private enum TypeKey: String, CodingKey { case type_ = "type" }
    private enum ContentKey: String, CodingKey {
        case text
        case imageUrl = "imageUrl"
        case audioUrl = "audioUrl"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type_ = try container.decode(String.self, forKey: .type_)
        let content = try decoder.container(keyedBy: ContentKey.self)
        switch type_ {
        case "inputText":
            self = .inputText(text: try content.decode(String.self, forKey: .text))
        case "inputImage":
            self = .inputImage(imageUrl: try content.decode(String.self, forKey: .imageUrl))
        case "inputAudio":
            self = .inputAudio(audioUrl: try content.decode(String.self, forKey: .audioUrl))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type_, in: container,
                debugDescription: "Unknown content item type: \(type_)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        var content = encoder.container(keyedBy: ContentKey.self)
        switch self {
        case .inputText(let text):
            try container.encode("inputText", forKey: .type_)
            try content.encode(text, forKey: .text)
        case .inputImage(let imageUrl):
            try container.encode("inputImage", forKey: .type_)
            try content.encode(imageUrl, forKey: .imageUrl)
        case .inputAudio(let audioUrl):
            try container.encode("inputAudio", forKey: .type_)
            try content.encode(audioUrl, forKey: .audioUrl)
        }
    }
}

// MARK: - Legacy normalization

/// Normalizes dynamic tool specifications, handling both canonical and legacy formats.
public func normalizeDynamicToolSpecs(_ values: [JSONValue]) throws -> [DynamicToolSpec] {
    func hasLegacyFields(_ value: JSONValue) -> Bool {
        guard case .object(let obj) = value else { return false }
        return obj["namespace"] != nil || obj["exposeToContext"] != nil || obj["type"] == nil
    }

    let hasLegacy = values.contains(where: { hasLegacyFields($0) })
        || values.contains(where: { value in
            guard case .object(let obj) = value,
                  case .array(let tools)? = obj["tools"] else { return false }
            return tools.contains(where: { hasLegacyFields($0) })
        })
    let hasCanonical = values.contains(where: { value in
        guard case .object(let obj) = value else { return false }
        return obj["type"] != nil
    })

    if hasLegacy && hasCanonical {
        throw DynamicToolNormalizationError.mixedFormats
    }

    if !hasLegacy {
        let data = try JSONEncoder().encode(values)
        return try JSONDecoder().decode([DynamicToolSpec].self, from: data)
    }

    var tools: [(String?, DynamicToolFunctionSpec)] = []
    for value in values {
        let data = try JSONEncoder().encode(value)
        let legacy = try JSONDecoder().decode(LegacyDynamicToolSpec.self, from: data)
        let function = DynamicToolFunctionSpec(
            name: legacy.name,
            description: legacy.description,
            inputSchema: legacy.inputSchema,
            deferLoading: legacy.deferLoading ?? legacy.exposeToContext.map { !$0 } ?? false
        )
        tools.append((legacy.namespace, function))
    }
    return groupDynamicToolsByNamespace(tools)
}

/// Groups flat (namespace, function) pairs into `DynamicToolSpec` entries.
public func groupDynamicToolsByNamespace(
    _ tools: [(String?, DynamicToolFunctionSpec)]
) -> [DynamicToolSpec] {
    var grouped: [DynamicToolSpec] = []
    var namespaceIndices: [String: Int] = [:]
    for (namespace, function) in tools {
        guard let namespace else {
            grouped.append(.function(function))
            continue
        }
        let nsTool = DynamicToolNamespaceTool.function(function)
        if let idx = namespaceIndices[namespace] {
            if case .namespace(var ns) = grouped[idx] {
                ns.tools.append(nsTool)
                grouped[idx] = .namespace(ns)
            }
        } else {
            namespaceIndices[namespace] = grouped.count
            grouped.append(.namespace(DynamicToolNamespaceSpec(
                name: namespace, tools: [nsTool]
            )))
        }
    }
    return grouped
}

private struct LegacyDynamicToolSpec: Codable {
    var namespace: String?
    var name: String
    var description: String
    var inputSchema: JSONValue
    var deferLoading: Bool?
    var exposeToContext: Bool?

    enum CodingKeys: String, CodingKey {
        case namespace, name, description
        case inputSchema = "inputSchema"
        case deferLoading = "deferLoading"
        case exposeToContext = "exposeToContext"
    }
}

enum DynamicToolNormalizationError: Error {
    case mixedFormats
}
