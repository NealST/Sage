//
//  mcp_tool_call.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_tool_call.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  The 2,510-line caller talks to MCPStdioClient in the Sage app. This
//  file keeps invocation metadata used by session/tools.
//

import Foundation

public struct McpToolCallRequest: Equatable, Sendable {
    public var serverName: String
    public var toolName: String
    public var argumentsJSON: String

    public init(serverName: String, toolName: String, argumentsJSON: String) {
        self.serverName = serverName
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

public struct McpToolCallResult: Equatable, Sendable {
    public var content: String
    public var isError: Bool

    public init(content: String, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}
