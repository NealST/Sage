//
//  mcp_tool_approval_templates.swift
//  CodexCore
//
//  Port of codex-rs/core/src/mcp_tool_approval_templates.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct McpToolApprovalTemplate: Equatable, Sendable {
    public var serverName: String
    public var toolName: String
    public var summary: String

    public init(serverName: String, toolName: String, summary: String) {
        self.serverName = serverName
        self.toolName = toolName
        self.summary = summary
    }
}
