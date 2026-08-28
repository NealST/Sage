//
//  CapabilityStore+ToolCalls.swift
//  Sage
//

import Foundation

extension CapabilityStore {
    func callMCPTool(
        qualifiedName: String,
        argumentsJSON: String,
        temporaryWriteRoots: [URL] = []
    ) async throws -> String {
        let target = try mcpToolTarget(qualifiedName)
        guard let server = mcpServers.first(where: { server in
            server.name == target.serverName && server.enabled
        }) else {
            throw MCPStdioClient.ClientError.notRunning
        }
        if temporaryWriteRoots.isEmpty {
            guard let client = clients[server.id] else {
                throw MCPStdioClient.ClientError.notRunning
            }
            return try await client.callTool(
                name: target.toolName,
                argumentsJSON: argumentsJSON
            )
        }

        await connect(serverID: server.id, writableRoots: temporaryWriteRoots)
        guard let writableClient = clients[server.id] else {
            throw MCPStdioClient.ClientError.notRunning
        }
        do {
            let result = try await writableClient.callTool(
                name: target.toolName,
                argumentsJSON: argumentsJSON
            )
            await connect(serverID: server.id)
            return result
        } catch {
            await connect(serverID: server.id)
            throw error
        }
    }

    func mcpToolDefinitions() -> [ToolDefinition] {
        mcpTools.map { tool in
            ToolDefinition(
                name: tool.qualifiedName,
                description: "[\(tool.serverName)] \(tool.description)",
                parameters: tool.inputSchema,
                requiresConfirmation: tool.readOnlyHint != true
            )
        }
    }

    private func mcpToolTarget(_ qualifiedName: String) throws -> (
        serverName: String,
        toolName: String
    ) {
        guard qualifiedName.hasPrefix("mcp__") else {
            throw MCPStdioClient.ClientError.invalidResponse("Not an MCP tool")
        }
        let rest = String(qualifiedName.dropFirst(5))
        guard let separator = rest.range(of: "__") else {
            throw MCPStdioClient.ClientError.invalidResponse("Malformed MCP tool name")
        }
        return (
            String(rest[..<separator.lowerBound]),
            String(rest[separator.upperBound...])
        )
    }
}
