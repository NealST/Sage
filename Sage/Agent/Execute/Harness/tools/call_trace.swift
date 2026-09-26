//
//  call_trace.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/call_trace.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  otel is trimmed to NSLog. Events still omit arguments and output.
//

import CodexProtocol
import Foundation

enum ToolCallTraceSource: Equatable, Sendable {
    case direct
    case codeMode

    func asString() -> String {
        switch self {
        case .direct: return "direct"
        case .codeMode: return "code_mode"
        }
    }
}

enum ToolCallReceipt: Equatable, Sendable {
    case modelTurn(String)
    case codeModeBroker(cellId: String?, runtimeToolCallId: String?)
}

func toolCallReceived(
    threadId: ThreadId,
    toolName: ToolName,
    callId: String,
    receipt: ToolCallReceipt
) {
    let turnId: String?
    let source: ToolCallTraceSource
    let cellId: String?
    let runtimeToolCallId: String?
    switch receipt {
    case .modelTurn(let id):
        turnId = id
        source = .direct
        cellId = nil
        runtimeToolCallId = nil
    case .codeModeBroker(let cell, let runtime):
        turnId = nil
        source = .codeMode
        cellId = cell
        runtimeToolCallId = runtime
    }
    NSLog(
        "codex.tool_call_received thread=%@ turn=%@ call=%@ tool=%@ ns=%@ source=%@ cell=%@ runtime=%@",
        threadId.description,
        turnId ?? "",
        callId,
        toolName.name,
        toolCallNamespace(toolName),
        source.asString(),
        cellId ?? "",
        runtimeToolCallId ?? ""
    )
}

func toolCallResultReady(
    threadId: ThreadId,
    turnId: String,
    toolName: ToolName,
    callId: String,
    source: ToolCallTraceSource
) {
    NSLog(
        "codex.tool_result_ready thread=%@ turn=%@ call=%@ tool=%@ ns=%@ source=%@",
        threadId.description,
        turnId,
        callId,
        toolName.name,
        toolCallNamespace(toolName),
        source.asString()
    )
}

func toolCallNamespace(_ toolName: ToolName) -> String {
    if let namespace = toolName.namespace, !namespace.isEmpty {
        return namespace
    }
    return DEFAULT_FUNCTION_NAMESPACE
}
