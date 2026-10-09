//
//  mcp.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  One handler per catalog tool. A prepared transport runs
//  `handleMcpToolCall`. `onMcpCall` remains the string seam.
//

import CodexCore
import CodexProtocol

struct McpHandler: CoreToolRuntime {
    var name: ToolName
    var toolSpec: ToolSpec
    var serverName: String?
    var toolExposure: ToolExposure

    init(
        name: ToolName,
        spec: ToolSpec,
        serverName: String? = nil,
        exposure: ToolExposure = .direct
    ) {
        self.name = name
        self.toolSpec = spec
        self.serverName = serverName
        self.toolExposure = exposure
    }

    func toolName() -> ToolName { name }
    func spec() -> ToolSpec { toolSpec }
    func exposure() -> ToolExposure { toolExposure }
    func mcpServerName() -> String? { serverName }
    func searchInfo() -> ToolSearchInfo? {
        ToolSearchInfo(
            description: toolSpec.name(),
            keywords: [flatToolName(name)],
            source: serverName.map { ToolSearchSourceInfo(name: $0, description: nil) }
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        if invocation.mcpToolTransport != nil {
            return try await handlePreparedCall(invocation)
        }
        return try await invokeMcp(invocation, name: flatToolName(name))
    }

    private func handlePreparedCall(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel("mcp handler received unsupported payload")
        }
        let tool = flatToolName(name)
        let server = serverName ?? ""
        let prepared = server.isEmpty
            ? nil
            : PreparedMcpToolCall(serverName: server, toolName: tool, enabled: true)
        let transport = invocation.mcpToolTransport ?? { _ in
            throw McpToolCallFailure("MCP transport is not attached")
        }
        let handled = await handleMcpToolCall(
            server: server,
            toolName: tool,
            arguments: arguments,
            prepared: prepared,
            inputModalities: invocation.mcpInputModalities,
            transport: transport
        )
        return boxedToolOutput(
            FunctionToolOutput.fromText(
                mcpToolResultText(handled.result),
                success: handled.result.isError != true
            )
        )
    }
}
