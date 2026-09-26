//
//  mcp_attribution.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/executed_tool_calls/mcp_attribution.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexProtocol

struct McpAttributionRecord: Equatable, Sendable {
    var toolName: String
    var serverName: String?
    var source: String
}

struct McpAttributionRecorder: Sendable {
    private var records: [String: McpAttributionRecord] = [:]

    mutating func record(callId: String, toolName: String, serverName: String?) {
        records[callId] = McpAttributionRecord(
            toolName: toolName,
            serverName: serverName,
            source: serverName == nil ? "harness" : "mcp"
        )
    }

    func attribution(for callId: String) -> McpAttributionRecord? {
        records[callId]
    }
}
