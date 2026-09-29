//
//  tool_result.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/tool_result.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Preview truncation is faithful. Emit is os.Logger (no tracing macros).
//

import CodexProtocol
import CodexUtils
import Foundation
import os

private let truncationNotice = "[... telemetry preview truncated ...]"
private let nextToolResultSeq = OSAllocatedUnfairLock(initialState: UInt64(1))

func nextToolResultSequence() -> UInt64 {
    nextToolResultSeq.withLock { value in
        let current = value
        value &+= 1
        return current
    }
}

public struct ToolResultEvent: Sendable {
    public var toolName: ToolName
    public var callId: String
    public var arguments: String
    public var mcpServer: String
    public var mcpServerOrigin: String
    public var duration: Duration
    public var success: Bool
    public var output: String

    public init(
        toolName: ToolName,
        callId: String,
        arguments: String,
        mcpServer: String = "",
        mcpServerOrigin: String = "",
        duration: Duration,
        success: Bool,
        output: String
    ) {
        self.toolName = toolName
        self.callId = callId
        self.arguments = arguments
        self.mcpServer = mcpServer
        self.mcpServerOrigin = mcpServerOrigin
        self.duration = duration
        self.success = success
        self.output = output
    }
}

public func emitToolResult(
    telemetry: SessionTelemetry,
    limits: ToolResultLogConfig,
    event: ToolResultEvent
) {
    let preview = telemetryPreview(event.output, limits: limits)
    let seq = nextToolResultSequence()
    let common: [String: String] = [
        "event.name": "codex.tool_result",
        "tool_result_seq": String(seq),
        "tool_name": event.toolName.name,
        "tool_namespace": toolNamespace(event.toolName),
        "call_id": event.callId,
        "duration_ms": String(Int(event.duration.milliseconds)),
        "success": event.success ? "true" : "false",
        "output_truncated": preview.truncated ? "true" : "false",
    ]
    var log = [
        "agent_name": telemetry.metadata.agentName,
        "arguments": event.arguments,
        "output": preview.text,
        "mcp_server": event.mcpServer,
        "mcp_server_origin": event.mcpServerOrigin,
    ]
    if let sku = telemetry.metadata.productSku {
        log["product_sku"] = sku
    }
    let trace: [String: String] = [
        "arguments_length": String(event.arguments.utf8.count),
        "output_length": String(event.output.utf8.count),
        "output_line_count": String(event.output.split(separator: "\n", omittingEmptySubsequences: false).count),
        "tool_origin": event.mcpServer.isEmpty ? "builtin" : "mcp",
        "mcp_tool": event.mcpServer.isEmpty ? "false" : "true",
    ]
    logAndTraceOtelEvent(telemetry, common: common, log: log, trace: trace)
}

public struct ToolResultPreview: Equatable, Sendable {
    public var text: String
    public var truncated: Bool
}

public func telemetryPreview(_ content: String, limits: ToolResultLogConfig) -> ToolResultPreview {
    let prefix = String(takeBytesAtCharBoundary(content, maxb: limits.maxBytes))
    if prefix.utf8.count == content.utf8.count {
        return ToolResultPreview(text: content, truncated: false)
    }
    let separator = prefix.isEmpty || prefix.hasSuffix("\n") ? "" : "\n"
    return ToolResultPreview(text: prefix + separator + truncationNotice, truncated: true)
}
