//
//  mcp.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/mcp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  MCP transport, approval, and Session services wait for Phase 5. This
//  adapter registers one handler per MCP tool name and forwards through
//  onMcpCall.
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
        try await invokeMcp(invocation, name: flatToolName(name))
    }
}
