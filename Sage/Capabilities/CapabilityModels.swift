//
//  CapabilityModels.swift
//  Sage
//

import Foundation

nonisolated struct SkillRecord: Identifiable, Codable, Sendable, Equatable {
    var id: String { name }
    var name: String
    var description: String
    var path: String
    var enabled: Bool
    var sourceLabel: String
}

nonisolated enum MCPServerStatus: String, Codable, Sendable, Equatable {
    case disabled
    case disconnected
    case connecting
    case connected
    case error
}

nonisolated struct MCPServerConfig: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var enabled: Bool
    /// Runtime-only fields are not persisted.
    var status: MCPServerStatus
    var statusMessage: String?
    var toolCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, command, args, env, enabled
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        command: String,
        args: [String] = [],
        env: [String: String] = [:],
        enabled: Bool = true,
        status: MCPServerStatus = .disconnected,
        statusMessage: String? = nil,
        toolCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.enabled = enabled
        self.status = enabled ? status : .disabled
        self.statusMessage = statusMessage
        self.toolCount = toolCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        status = enabled ? .disconnected : .disabled
        statusMessage = nil
        toolCount = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
        try container.encode(args, forKey: .args)
        try container.encode(env, forKey: .env)
        try container.encode(enabled, forKey: .enabled)
    }
}

nonisolated struct MCPFileSnapshot: Codable, Sendable {
    var mcpServers: [MCPServerConfig]
}

nonisolated struct SkillStateSnapshot: Codable, Sendable {
    /// skill name → enabled
    var enabled: [String: Bool]
}

nonisolated struct MCPToolInfo: Identifiable, Sendable, Equatable {
    var id: String { qualifiedName }
    var serverID: String
    var serverName: String
    var name: String
    var description: String
    var inputSchema: JSONValue

    var qualifiedName: String {
        "mcp__\(serverName)__\(name)"
    }
}
