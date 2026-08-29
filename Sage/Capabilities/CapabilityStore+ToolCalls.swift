//
//  CapabilityStore+ToolCalls.swift
//  Sage
//

import Foundation

extension CapabilityStore {
    func callMCPTool(
        qualifiedName: String,
        argumentsJSON: String,
        temporaryWriteRoots: [URL] = [],
        allowsProtectedMetadataWrites: Bool = false
    ) async throws -> String {
        let target = try mcpToolTarget(qualifiedName)
        guard let server = mcpServers.first(where: { server in
            server.id == target.serverID && server.enabled
        }) else {
            throw MCPStdioClient.ClientError.notRunning
        }
        await callCoordinator.acquire(serverID: server.id)
        do {
            try Task.checkCancellation()
            let result = try await callMCPTool(
                target: target,
                server: server,
                argumentsJSON: argumentsJSON,
                temporaryWriteRoots: temporaryWriteRoots,
                allowsProtectedMetadataWrites: allowsProtectedMetadataWrites
            )
            await callCoordinator.release(serverID: server.id)
            return result
        } catch {
            await callCoordinator.release(serverID: server.id)
            throw error
        }
    }

    private func callMCPTool(
        target: (serverID: String, toolName: String),
        server: MCPServerConfig,
        argumentsJSON: String,
        temporaryWriteRoots: [URL],
        allowsProtectedMetadataWrites: Bool
    ) async throws -> String {
        if temporaryWriteRoots.isEmpty {
            guard let client = clients[server.id] else {
                throw MCPStdioClient.ClientError.notRunning
            }
            return try await client.callTool(
                name: target.toolName,
                argumentsJSON: argumentsJSON
            )
        }

        await connect(
            serverID: server.id,
            writableRoots: temporaryWriteRoots,
            allowsProtectedMetadataWrites: allowsProtectedMetadataWrites
        )
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
                requiresConfirmation: tool.localWriteHint || tool.readOnlyHint == false
            )
        }
    }

    private func mcpToolTarget(_ qualifiedName: String) throws -> (
        serverID: String,
        toolName: String
    ) {
        guard qualifiedName.hasPrefix("mcp__") else {
            throw MCPStdioClient.ClientError.invalidResponse("Not an MCP tool")
        }
        let rest = String(qualifiedName.dropFirst(5))
        guard let separator = rest.range(of: "__") else {
            throw MCPStdioClient.ClientError.invalidResponse("Malformed MCP tool name")
        }
        let serverID = String(rest[..<separator.lowerBound])
        let toolName = String(rest[separator.upperBound...])
        guard mcpTools.contains(where: { tool in
            tool.serverID == serverID && tool.name == toolName
        }) || mcpServers.contains(where: { $0.id == serverID }) else {
            throw MCPStdioClient.ClientError.invalidResponse("Unknown MCP tool")
        }
        return (serverID, toolName)
    }
}
