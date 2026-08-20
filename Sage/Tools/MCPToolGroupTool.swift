//
//  MCPToolGroupTool.swift
//  Sage
//
//  Progressive disclosure for large MCP catalogs.
//

import Foundation

nonisolated enum MCPToolGroupTool {
    static let prefix = "mcp_group__"
    static let groupingThreshold = 20

    static func isGroupTool(_ name: String) -> Bool {
        name.hasPrefix(prefix)
    }

    static func groupedDefinitions(
        _ tools: [ToolDefinition],
        unlockedServerNames: Set<String>
    ) -> [ToolDefinition] {
        guard tools.count > groupingThreshold else { return tools }

        let groups = Dictionary(grouping: tools) { serverName(fromQualifiedTool: $0.name) ?? "" }
        var result: [ToolDefinition] = []
        for server in groups.keys.sorted() where !server.isEmpty {
            let definitions = groups[server] ?? []
            if unlockedServerNames.contains(server) {
                result.append(contentsOf: definitions)
            } else {
                result.append(groupDefinition(server: server, tools: definitions))
            }
        }
        return result
    }

    static func groupDefinition(server: String, tools: [ToolDefinition]) -> ToolDefinition {
        let summary = tools
            .sorted { $0.name < $1.name }
            .prefix(30)
            .map { definition in
                let shortName = definition.name
                    .split(separator: "__", maxSplits: 2)
                    .last
                    .map(String.init) ?? definition.name
                return "\(shortName): \(definition.description)"
            }
            .joined(separator: "\n")
        let suffix = tools.count > 30 ? "\n… \(tools.count - 30) more tools" : ""
        return ToolDefinition(
            name: prefix + server,
            description: """
            Unlock MCP server '\(server)' for this task. Call this before using one of its tools.
            Available tools:
            \(summary)\(suffix)
            """,
            parameters: .schemaObject(properties: [:]),
            requiresConfirmation: false
        )
    }

    static func execute(
        name: String,
        availableTools: [ToolDefinition]
    ) async throws -> String {
        guard let server = serverName(fromGroupTool: name) else {
            throw ToolError.invalidArguments("Malformed MCP group tool name.")
        }
        let tools = availableTools.filter {
            serverName(fromQualifiedTool: $0.name) == server
        }
        guard !tools.isEmpty else {
            throw ToolError.operationFailed("MCP server '\(server)' has no available tools.")
        }
        guard let repository = ActiveTaskContext.repository,
              let taskID = ActiveTaskContext.taskID
        else {
            throw ToolError.operationFailed("MCP groups are unavailable outside an active task.")
        }

        var names = ActiveTaskContext.unlockedMCPServerNames
        names.insert(server)
        try await repository.updateUnlockedMCPServers(taskID: taskID, names: names)
        await ActiveTaskContext.applyUnlockedMCPServers?(names)

        let toolNames = tools.map(\.name).sorted().joined(separator: "\n")
        return "Unlocked MCP server '\(server)' for this task:\n\(toolNames)"
    }

    static func serverName(fromQualifiedTool name: String) -> String? {
        guard name.hasPrefix("mcp__") else { return nil }
        let rest = name.dropFirst(5)
        guard let separator = rest.range(of: "__") else { return nil }
        return String(rest[..<separator.lowerBound])
    }

    static func serverName(fromGroupTool name: String) -> String? {
        guard name.hasPrefix(prefix) else { return nil }
        let server = String(name.dropFirst(prefix.count))
        return server.isEmpty ? nil : server
    }
}
