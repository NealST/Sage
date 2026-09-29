//
//  wait_agent_v2.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/wait.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and mailbox activity poll are live when
//  LocalAgentControl is attached. Live input-queue wait waits on Session.
//

import CodexCore
import CodexProtocol

struct WaitAgentV2Args: Decodable, Equatable, Sendable {
    var timeoutMs: Int64?

    enum CodingKeys: String, CodingKey {
        case timeoutMs = "timeout_ms"
    }
}

enum WaitOutcome: Equatable, Sendable {
    case mailboxActivity
    case steered
    case timedOut
}

struct WaitAgentV2Result: Encodable, Equatable, Sendable, ToolOutput {
    var message: String
    var timedOut: Bool

    enum CodingKeys: String, CodingKey {
        case message
        case timedOut = "timed_out"
    }

    static func fromOutcome(
        _ outcome: WaitOutcome,
        requestedTimeoutMs: Int64?,
        timeoutMs: Int64
    ) -> WaitAgentV2Result {
        var message: String
        switch outcome {
        case .mailboxActivity:
            message = "Wait completed."
        case .steered:
            message = "Wait interrupted by new input."
        case .timedOut:
            message = "Wait timed out."
        }
        if let requestedTimeoutMs, requestedTimeoutMs < timeoutMs {
            message +=
                "\n\nRequested timeout of \(requestedTimeoutMs)ms was clamped to the minimum of \(timeoutMs)ms."
        }
        return WaitAgentV2Result(message: message, timedOut: outcome == .timedOut)
    }

    func logOutput() -> String { toolOutputJsonText(self, toolName: "wait_agent") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: nil, toolName: "wait_agent")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "wait_agent")
    }
}

func resolveWaitAgentV2TimeoutMs(
    requestedTimeoutMs: Int64?,
    minTimeoutMs: Int64 = MIN_WAIT_TIMEOUT_MS,
    maxTimeoutMs: Int64 = MAX_WAIT_TIMEOUT_MS,
    defaultTimeoutMs: Int64 = DEFAULT_WAIT_TIMEOUT_MS
) throws -> Int64 {
    switch requestedTimeoutMs {
    case let ms? where ms > maxTimeoutMs:
        throw FunctionCallError.respondToModel("timeout_ms must be at most \(maxTimeoutMs)")
    case let ms?:
        return max(ms, minTimeoutMs)
    case nil:
        return defaultTimeoutMs
    }
}

struct WaitAgentV2Handler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(plain: "wait_agent") }
    func spec() -> ToolSpec { createWaitAgentToolV2() }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: WaitAgentV2Args = try parseArguments(arguments)
        let timeoutMs = try resolveWaitAgentV2TimeoutMs(requestedTimeoutMs: args.timeoutMs)
        let control = try requireLocalAgentControl(invocation)
        let caller = try requireCallerThreadId(invocation)
        let outcome: WaitOutcome = control.runtime.delivery.consumeActivity(caller)
            ? .mailboxActivity
            : .timedOut
        return WaitAgentV2Result.fromOutcome(
            outcome,
            requestedTimeoutMs: args.timeoutMs,
            timeoutMs: timeoutMs
        )
    }
}
