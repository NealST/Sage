//
//  mcp_policy.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/mcp_policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Managed MCP restrictions. Upstream derives only `Deserialize` (plus a
//  plain `EnvironmentMcpPolicy` with no serde at all), so these types are
//  `Decodable`-only. Untagged enums decode via buffered `JSONValue`, trying
//  variants in declaration order like serde.
//

import Foundation

/// Additional managed MCP restrictions supplied by an environment owner.
/// (Upstream has no serde derives on this struct.)
public struct EnvironmentMcpPolicy: Equatable, Sendable {
    public var servers: [String: McpServerRequirement]?
    public var plugins: [String: PluginMcpRequirements]?

    public init(
        servers: [String: McpServerRequirement]? = nil,
        plugins: [String: PluginMcpRequirements]? = nil
    ) {
        self.servers = servers
        self.plugins = plugins
    }
}

/// serde `untagged`: `{ "command": "..." }` or `{ "url": "..." }`.
public enum McpServerIdentity: Equatable, Sendable {
    case command(command: String)
    case url(url: String)
}

extension McpServerIdentity: Decodable {
    public init(from decoder: any Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard case .object(let object) = value else {
            throw DecodingError.typeMismatch(
                McpServerIdentity.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "data did not match any variant of untagged enum McpServerIdentity"
                )
            )
        }
        // Variant order matters: Command is tried before Url.
        if case .string(let command)? = object["command"] {
            self = .command(command: command)
        } else if case .string(let url)? = object["url"] {
            self = .url(url: url)
        } else {
            throw DecodingError.typeMismatch(
                McpServerIdentity.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "data did not match any variant of untagged enum McpServerIdentity"
                )
            )
        }
    }
}

/// String matching operations available to managed MCP server matchers.
/// serde `tag = "match"`, `rename_all = "snake_case"`, `deny_unknown_fields`.
public enum McpServerValueMatcher: Equatable, Sendable {
    case exact(value: String)
    case prefix(value: String)
    case regex(expression: String)
}

extension McpServerValueMatcher: Decodable {
    private enum CodingKeys: String, CodingKey {
        case match
        case value
        case expression
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let match = try container.decode(String.self, forKey: .match)
        switch match {
        case "exact":
            try rejectUnknownFields(in: decoder, allowed: Set<CodingKeys>([.match, .value]), type: "McpServerValueMatcher")
            self = .exact(value: try container.decode(String.self, forKey: .value))
        case "prefix":
            try rejectUnknownFields(in: decoder, allowed: Set<CodingKeys>([.match, .value]), type: "McpServerValueMatcher")
            self = .prefix(value: try container.decode(String.self, forKey: .value))
        case "regex":
            try rejectUnknownFields(in: decoder, allowed: Set<CodingKeys>([.match, .expression]), type: "McpServerValueMatcher")
            self = .regex(expression: try container.decode(String.self, forKey: .expression))
        default:
            throw DecodingError.typeMismatch(
                McpServerValueMatcher.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown variant `\(match)`, expected `exact`, `prefix` or `regex`"
                )
            )
        }
    }
}

/// serde `deny_unknown_fields`.
public struct McpServerCommandMatcher: Equatable, Sendable {
    public var executable: String
    public var args: [McpServerValueMatcher]

    public init(executable: String, args: [McpServerValueMatcher]) {
        self.executable = executable
        self.args = args
    }
}

extension McpServerCommandMatcher: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case executable
        case args
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "McpServerCommandMatcher")
        executable = try container.decode(String.self, forKey: .executable)
        args = try container.decode([McpServerValueMatcher].self, forKey: .args)
    }
}

/// serde `deny_unknown_fields`.
private struct RawMcpServerCommandIdentity: Decodable {
    var command: McpServerCommandMatcher

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "RawMcpServerCommandIdentity")
        command = try container.decode(McpServerCommandMatcher.self, forKey: .command)
    }
}

/// serde `deny_unknown_fields`.
private struct RawMcpServerUrlIdentity: Decodable {
    var url: McpServerValueMatcher

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case url
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try rejectUnknownFields(in: decoder, keys: CodingKeys.self, type: "RawMcpServerUrlIdentity")
        url = try container.decode(McpServerValueMatcher.self, forKey: .url)
    }
}

/// A requirement for one named MCP server.
///
/// The `identity` variant preserves the released exact-match contract. The
/// command and URL variants are the normalized matcher-based forms accepted
/// under the `identity` key.
public enum McpServerRequirement: Equatable, Sendable {
    case identity(identity: McpServerIdentity)
    case command(McpServerCommandMatcher)
    case url(McpServerValueMatcher)
}

extension McpServerRequirement: Decodable {
    private enum CodingKeys: String, CodingKey {
        case identity
    }

    public init(from decoder: any Decoder) throws {
        // RawMcpServerRequirement { identity } — no deny_unknown_fields.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(JSONValue.self, forKey: .identity)
        // RawMcpServerIdentity (untagged): Exact, then Command, then Url.
        if let exact = try? raw.decoded(as: McpServerIdentity.self) {
            self = .identity(identity: exact)
        } else if let command = try? raw.decoded(as: RawMcpServerCommandIdentity.self) {
            self = .command(command.command)
        } else if let url = try? raw.decoded(as: RawMcpServerUrlIdentity.self) {
            self = .url(url.url)
        } else {
            throw DecodingError.typeMismatch(
                McpServerRequirement.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "data did not match any variant of untagged enum RawMcpServerIdentity"
                )
            )
        }
    }
}

/// Managed MCP server requirements for one plugin.
public struct PluginMcpRequirements: Equatable, Sendable {
    public var mcpServers: [String: McpServerRequirement]?

    public init(mcpServers: [String: McpServerRequirement]? = nil) {
        self.mcpServers = mcpServers
    }

    public var isEmpty: Bool {
        mcpServers?.isEmpty ?? true
    }
}

extension PluginMcpRequirements: Decodable {
    private enum CodingKeys: String, CodingKey {
        case mcpServers = "mcp_servers"
    }
}
