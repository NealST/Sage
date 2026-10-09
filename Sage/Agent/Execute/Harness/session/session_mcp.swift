//
//  session_mcp.swift
//  Sage
//
//  Port of codex-rs/core/src/session/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Elicitation review stays out. This file is the session binding:
//  connect enabled servers, list the model-visible catalog, and run one
//  prepared tool call through `handleMcpToolCall`.
//

import CodexCore
import CodexProtocol
import Foundation

extension Session {
    func ensureMcpConnected() async {
        await services.ensureMcpConnected?()
    }

    func listMcpTools() -> [String] {
        if !services.mcpVisibleTools.isEmpty {
            return services.mcpVisibleTools.map(\.name)
        }
        return services.modelVisibleMcpToolNames
    }

    func callMcpTool(
        server: String,
        toolName: String,
        arguments: String,
        enabled: Bool = true,
        inputModalities: [InputModality] = defaultInputModalities()
    ) async -> HandledMcpToolCall {
        let prepared = services.mcpVisibleTools.contains { tool in
            tool.name == toolName && (tool.serverName == server || tool.serverName == nil)
        } ? PreparedMcpToolCall(serverName: server, toolName: toolName, enabled: enabled) : nil
        let transport = services.mcpToolTransport ?? { _ in
            throw McpToolCallFailure("MCP transport is not attached")
        }
        return await handleMcpToolCall(
            server: server,
            toolName: toolName,
            arguments: arguments,
            prepared: prepared,
            inputModalities: inputModalities,
            transport: transport
        )
    }
}
