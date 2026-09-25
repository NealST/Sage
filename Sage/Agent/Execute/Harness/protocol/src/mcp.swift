//
//  mcp.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  MCP (Model Context Protocol) types and helpers used inside the Codex
//  protocol. TS/JSON-schema derives are omitted; Codable conformance
//  preserves the same wire shapes.
//

import Foundation

// MARK: - McpServerConnectionStatus

public enum McpServerConnectionStatus: String, Codable, Equatable, Sendable {
    case notStarted
    case starting
    case connected
    case authenticationRequired
    case failed
    case cancelled
    case disabled
}

// MARK: - Extension IDs

public let openaiElicitationExtensionId = "openai/elicitation"
public let openaiFormExtensionId = "openai/form"
public let openaiStandardFormInputExtensionId = "openai/standard-form-input"
public let mcpAppUiExtensionId = "io.modelcontextprotocol/ui"
public let confirmationPoliciesMetaKey = "openai/confirmation_policies"

// MARK: - Node REPL helpers

public func isNodeReplBackedServer(_ server: String) -> Bool {
    server == "node_repl" || server == "cua_repl"
}

public func isNodeReplBackedConnector(_ server: String, connectorId: String?) -> Bool {
    isNodeReplBackedServer(server)
        || (server == "codex_apps" && connectorId == "connector_openai_browser")
}

public func isNodeReplBackedTool(name: String, namespace: String?) -> Bool {
    if let namespace {
        let stripped = namespace.hasPrefix("mcp__")
            ? String(namespace.dropFirst(5))
            : namespace
        let server = stripped.hasSuffix("__")
            ? String(stripped.dropLast(2))
            : stripped
        return isNodeReplBackedServer(server)
    }
    let name = name.hasPrefix("mcp__") ? String(name.dropFirst(5)) : name
    guard let idx = name.range(of: "__") else { return false }
    let server = String(name[name.startIndex..<idx.lowerBound])
    return isNodeReplBackedServer(server)
}

// MARK: - McpAttributionStatus

public enum McpAttributionStatus: String, Codable, Equatable, Sendable {
    case none
    case complete
    case attributionError = "attribution_error"
}

// MARK: - McpAttributionErrorReason

public enum McpAttributionErrorReason: String, Codable, Equatable, Sendable {
    case historyMissingCheckpoint = "history_missing_checkpoint"
    case checkpointInvalid = "checkpoint_invalid"
    case checkpointSourceConflict = "checkpoint_source_conflict"
    case sourceInvalid = "source_invalid"
    case recorderPoisoned = "recorder_poisoned"
    case restoredErrorUnknown = "restored_error_unknown"
    case payloadTooLarge = "payload_too_large"
    case serializationFailed = "serialization_failed"
    case unknown

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = McpAttributionErrorReason(rawValue: raw) ?? .unknown
    }
}

// MARK: - McpAttributionSource

public struct McpAttributionSource: Codable, Equatable, Sendable {
    public var connectorId: String?
    public var pluginId: String?
    public var serverName: String
    public var toolName: String
    public var firstTurnId: String

    enum CodingKeys: String, CodingKey {
        case connectorId = "connector_id"
        case pluginId = "plugin_id"
        case serverName = "server_name"
        case toolName = "tool_name"
        case firstTurnId = "first_turn_id"
    }
}

// MARK: - McpAttribution

public struct McpAttribution: Codable, Equatable, Sendable {
    public var status: McpAttributionStatus
    public var errorReason: McpAttributionErrorReason?
    public var sources: [McpAttributionSource]

    public init(
        status: McpAttributionStatus = .none,
        errorReason: McpAttributionErrorReason? = nil,
        sources: [McpAttributionSource] = []
    ) {
        self.status = status
        self.errorReason = errorReason
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case status
        case errorReason = "error_reason"
        case sources
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(McpAttributionStatus.self, forKey: .status)
        errorReason = try? container.decodeIfPresent(McpAttributionErrorReason.self, forKey: .errorReason)
        sources = try container.decodeIfPresent([McpAttributionSource].self, forKey: .sources) ?? []
    }
}

// MARK: - McpResourceOriginCheckpoint

public struct McpResourceOriginCheckpoint: Codable, Equatable, Sendable {
    public var origins: [McpResourceOrigin]
    public var turns: [String]
    public var currentTurnId: String?

    enum CodingKeys: String, CodingKey {
        case origins, turns
        case currentTurnId = "current_turn_id"
    }
}

// MARK: - McpResourceOrigin

public struct McpResourceOrigin: Codable, Equatable, Sendable {
    public var callId: String
    public var turnId: String?
    public var tool: String
    public var connectorId: String
    public var linkId: String?
    public var uri: String
    public var ambiguousAccount: Bool

    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case turnId = "turn_id"
        case tool
        case connectorId = "connector_id"
        case linkId = "link_id"
        case uri
        case ambiguousAccount = "ambiguous_account"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId)
        tool = try container.decode(String.self, forKey: .tool)
        connectorId = try container.decode(String.self, forKey: .connectorId)
        linkId = try container.decodeIfPresent(String.self, forKey: .linkId)
        uri = try container.decode(String.self, forKey: .uri)
        ambiguousAccount = try container.decodeIfPresent(Bool.self, forKey: .ambiguousAccount) ?? false
    }
}

// MARK: - ClientMcpExtensions

private let mcpClientOnlyExtensionIds: Set<String> = [openaiStandardFormInputExtensionId]

public struct ClientMcpExtensions: Equatable, Sendable {
    private var extensions: [String: JSONValue]

    public init(_ extensions: [(String, JSONValue)] = []) {
        self.extensions = Dictionary(extensions, uniquingKeysWith: { _, last in last })
    }

    public func contains(_ extensionId: String) -> Bool {
        extensions.keys.contains(extensionId)
    }

    public func get(_ extensionId: String) -> JSONValue? {
        extensions[extensionId]
    }

    public func forMcpServers() -> ClientMcpExtensions {
        ClientMcpExtensions(
            extensions
                .filter { !mcpClientOnlyExtensionIds.contains($0.key) }
                .map { ($0.key, $0.value) }
        )
    }

    public func makeIterator() -> Dictionary<String, JSONValue>.Iterator {
        extensions.makeIterator()
    }
}

// MARK: - RequestId

public enum RequestId: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case integer(Int64)

    public var description: String {
        switch self {
        case .string(let s): s
        case .integer(let i): "\(i)"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int64.self) {
            self = .integer(i)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .integer(let i): try container.encode(i)
        }
    }
}

// MARK: - McpServerInfo

public struct McpServerInfo: Codable, Equatable, Sendable {
    public var name: String
    public var title: String?
    public var version: String
    public var description: String?
    public var icons: [JSONValue]?
    public var websiteUrl: String?

    enum CodingKeys: String, CodingKey {
        case name, title, version, description, icons
        case websiteUrl = "websiteUrl"
    }
}

// MARK: - McpTool

public struct McpTool: Codable, Equatable, Sendable {
    public var name: String
    public var title: String?
    public var description: String?
    public var inputSchema: JSONValue
    public var outputSchema: JSONValue?
    public var annotations: JSONValue?
    public var icons: [JSONValue]?
    public var meta: JSONValue?

    enum CodingKeys: String, CodingKey {
        case name, title, description
        case inputSchema = "inputSchema"
        case outputSchema = "outputSchema"
        case annotations, icons
        case meta = "_meta"
    }
}

// MARK: - McpResource

public struct McpResource: Codable, Equatable, Sendable {
    public var annotations: JSONValue?
    public var description: String?
    public var mimeType: String?
    public var name: String
    public var size: Int64?
    public var title: String?
    public var uri: String
    public var icons: [JSONValue]?
    public var meta: JSONValue?

    enum CodingKeys: String, CodingKey {
        case annotations, description, name, title, uri, icons
        case mimeType = "mimeType"
        case size
        case meta = "_meta"
    }
}

// MARK: - ResourceContent

public enum ResourceContent: Codable, Equatable, Sendable {
    case text(uri: String, mimeType: String?, text: String, meta: JSONValue?)
    case blob(uri: String, mimeType: String?, blob: String, meta: JSONValue?)

    private enum TypeKey: String, CodingKey {
        case uri, mimeType, text, blob
        case meta = "_meta"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let uri = try container.decode(String.self, forKey: .uri)
        let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        let meta = try container.decodeIfPresent(JSONValue.self, forKey: .meta)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(uri: uri, mimeType: mimeType, text: text, meta: meta)
        } else {
            let blob = try container.decode(String.self, forKey: .blob)
            self = .blob(uri: uri, mimeType: mimeType, blob: blob, meta: meta)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .text(let uri, let mimeType, let text, let meta):
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(meta, forKey: .meta)
        case .blob(let uri, let mimeType, let blob, let meta):
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encode(blob, forKey: .blob)
            try container.encodeIfPresent(meta, forKey: .meta)
        }
    }
}

// MARK: - McpResourceTemplate

public struct McpResourceTemplate: Codable, Equatable, Sendable {
    public var annotations: JSONValue?
    public var uriTemplate: String
    public var name: String
    public var title: String?
    public var description: String?
    public var mimeType: String?

    enum CodingKeys: String, CodingKey {
        case annotations
        case uriTemplate = "uriTemplate"
        case name, title, description
        case mimeType = "mimeType"
    }
}

// MARK: - CallToolResult

public struct CallToolResult: Codable, Equatable, Sendable {
    public var content: [JSONValue]
    public var structuredContent: JSONValue?
    public var isError: Bool?
    public var meta: JSONValue?

    enum CodingKeys: String, CodingKey {
        case content
        case structuredContent = "structuredContent"
        case isError = "isError"
        case meta = "_meta"
    }
}
