//
//  executed_tool_calls.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/executed_tool_calls.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session / history / code-mode cell binding wait for Phase 5–7. The
//  recorder keeps in-memory attempted calls without dispatching tools.
//

import CodexProtocol
import Foundation

let MAX_PENDING_EXECUTED_TOOL_CALLS = 256
let MAX_RETAINED_DIRECT_METADATA_BYTES = 1024 * 1024

struct RecordedExecutedToolCall: Equatable, Sendable {
    var callId: String
    var toolName: String
    var arguments: String
    var output: String?
    var success: Bool?
}

final class ExecutedToolCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String: RecordedExecutedToolCall] = [:]
    private var retained: [RecordedExecutedToolCall] = []
    private var seen = SeenIds()
    private var mcpAttribution = McpAttributionRecorder()
    private var pendingDirectCalls = 0

    func prepare(call: ToolCall, source: ToolCallSource) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pending.count >= MAX_PENDING_EXECUTED_TOOL_CALLS { return false }
        if !seen.insert(call.callId) { return false }
        pending[call.callId] = RecordedExecutedToolCall(
            callId: call.callId,
            toolName: flatToolName(call.toolName),
            arguments: truncatedToolArgument(toolLogPayload(call.payload, source: source))
        )
        pendingDirectCalls += 1
        return true
    }

    func complete(callId: String, output: any ToolOutput) {
        lock.lock()
        defer { lock.unlock() }
        guard var record = pending.removeValue(forKey: callId) else { return }
        record.output = output.logOutput()
        record.success = output.successForLogging()
        retained.append(record)
        pendingDirectCalls = max(0, pendingDirectCalls - 1)
    }

    func cancel(callId: String) {
        lock.lock()
        defer { lock.unlock() }
        pending.removeValue(forKey: callId)
        pendingDirectCalls = max(0, pendingDirectCalls - 1)
    }

    func recordMcp(callId: String, toolName: String, serverName: String?) {
        lock.lock()
        defer { lock.unlock() }
        mcpAttribution.record(callId: callId, toolName: toolName, serverName: serverName)
    }

    func retainedCalls() -> [RecordedExecutedToolCall] {
        lock.lock()
        defer { lock.unlock() }
        return retained
    }
}
