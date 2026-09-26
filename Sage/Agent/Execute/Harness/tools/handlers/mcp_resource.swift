//
//  mcp_resource.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/mcp_resource.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  MCP transport waits for Phase 5. Handlers parse arguments and invoke
//  onMcpCall.
//

import CodexCore
import CodexProtocol
import Foundation

struct ListMcpResourcesArgs: Decodable {
    var server: String?
    var cursor: String?
}

struct ReadMcpResourceArgs: Decodable {
    var server: String
    var uri: String
}

struct ListMcpResourcesHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "list_mcp_resources") }
    func spec() -> ToolSpec { createListMcpResourcesTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        try await invokeMcp(invocation, name: "list_mcp_resources")
    }
}

struct ListMcpResourceTemplatesHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "list_mcp_resource_templates") }
    func spec() -> ToolSpec { createListMcpResourceTemplatesTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        try await invokeMcp(invocation, name: "list_mcp_resource_templates")
    }
}

struct ReadMcpResourceHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "read_mcp_resource") }
    func spec() -> ToolSpec { createReadMcpResourceTool() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "read_mcp_resource handler received unsupported payload"
            )
        }
        let args: ReadMcpResourceArgs = try parseArguments(arguments)
        return try await invokeMcp(
            invocation,
            name: "read_mcp_resource",
            arguments: .object(["server": .string(args.server), "uri": .string(args.uri)])
        )
    }
}

func invokeMcp(
    _ invocation: ToolInvocation,
    name: String,
    arguments: HarnessJSON? = nil
) async throws -> any ToolOutput {
    guard case .function(let raw) = invocation.payload else {
        throw FunctionCallError.respondToModel("\(name) handler received unsupported payload")
    }
    let json: HarnessJSON
    if let arguments {
        json = arguments
    } else if let data = raw.data(using: .utf8),
              let object = try? JSONDecoder().decode(HarnessJSON.self, from: data) {
        json = object
    } else {
        json = .object([:])
    }
    guard let onMcp = invocation.onMcpCall else {
        throw FunctionCallError.respondToModel("\(name) is not wired (Phase 5 MCP)")
    }
    guard let output = await onMcp(name, invocation.callId, json) else {
        throw FunctionCallError.respondToModel("\(name) was cancelled before receiving a response")
    }
    return boxedToolOutput(FunctionToolOutput.fromText(output, success: true))
}
