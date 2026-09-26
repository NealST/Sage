//
//  telemetry.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_tool_call/telemetry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct McpToolCallTelemetry: Equatable, Sendable {
    public var serverName: String
    public var toolName: String
    public var durationMs: Int64
    public var succeeded: Bool

    public init(serverName: String, toolName: String, durationMs: Int64, succeeded: Bool) {
        self.serverName = serverName
        self.toolName = toolName
        self.durationMs = durationMs
        self.succeeded = succeeded
    }
}
