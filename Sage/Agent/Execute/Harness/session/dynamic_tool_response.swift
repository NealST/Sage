//
//  dynamic_tool_response.swift
//  Sage
//
//  Port of `request_dynamic_tool` in
//  codex-rs/core/src/tools/handlers/dynamic.rs and
//  `notify_dynamic_tool_response` in codex-rs/core/src/session/mod.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  A dynamic tool call waits on the active turn, keyed by tool call id.
//  `Op::DynamicToolResponse` resumes that waiter and does not start a turn.
//  A missing waiter is ignored. A replacement call keeps the previous waiter
//  until the new call finishes, then the previous one returns nil.
//  ToolCallRuntime installs the handler callback.
//

import CodexProtocol
import Foundation

extension Session {
    /// rust `request_dynamic_tool`.
    func requestDynamicTool(
        turnContext: TurnContext,
        callId: String,
        namespace: String?,
        tool: String,
        arguments: CodexProtocol.JSONValue
    ) async -> DynamicToolResponse? {
        let replaced = ReplacedDynamicTool()
        let started = ContinuousClock.now
        let response: DynamicToolResponse? = await withCheckedContinuation { continuation in
            let decision = DynamicToolDecision(continuation)
            let startedItem = inProgressDynamicToolCall(
                callId: callId, namespace: namespace, tool: tool, arguments: arguments)
            if let turn = activeTurn {
                replaced.decision = turn.turnState.insertPendingDynamicTool(
                    key: callId, decision: decision)
                emitTurnItemStarted(turnContext, .dynamicToolCall(startedItem))
            } else {
                emitTurnItemStarted(turnContext, .dynamicToolCall(startedItem))
                decision.resume(nil)
            }
        }
        emitTurnItemCompleted(
            turnContext,
            .dynamicToolCall(
                finishedDynamicToolCall(
                    callId: callId,
                    namespace: namespace,
                    tool: tool,
                    arguments: arguments,
                    response: response,
                    duration: started.duration(to: .now)
                )
            )
        )
        replaced.decision?.resume(nil)
        return response
    }

    /// rust `Session::notify_dynamic_tool_response`.
    func notifyDynamicToolResponse(id: String, response: DynamicToolResponse) {
        guard let turn = activeTurn,
              let decision = turn.turnState.removePendingDynamicTool(key: id)
        else { return }
        decision.resume(response)
    }
}

private final class ReplacedDynamicTool: @unchecked Sendable {
    var decision: DynamicToolDecision?
}

private func inProgressDynamicToolCall(
    callId: String,
    namespace: String?,
    tool: String,
    arguments: CodexProtocol.JSONValue
) -> DynamicToolCallItem {
    DynamicToolCallItem(
        id: callId,
        namespace: namespace,
        tool: tool,
        arguments: arguments,
        status: .inProgress
    )
}

private func finishedDynamicToolCall(
    callId: String,
    namespace: String?,
    tool: String,
    arguments: CodexProtocol.JSONValue,
    response: DynamicToolResponse?,
    duration: Duration
) -> DynamicToolCallItem {
    if let response {
        return DynamicToolCallItem(
            id: callId,
            namespace: namespace,
            tool: tool,
            arguments: arguments,
            status: response.success ? .completed : .failed,
            contentItems: response.contentItems,
            success: response.success,
            duration: duration
        )
    }
    return DynamicToolCallItem(
        id: callId,
        namespace: namespace,
        tool: tool,
        arguments: arguments,
        status: .failed,
        contentItems: [],
        success: false,
        error: "dynamic tool call was cancelled before receiving a response",
        duration: duration
    )
}
