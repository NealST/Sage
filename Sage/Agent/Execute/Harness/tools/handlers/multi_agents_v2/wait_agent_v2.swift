//
//  wait_agent_v2.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/wait.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, mailbox activity, and steer waits are live
//  when LocalAgentControl is attached. Session InputQueue and
//  AgentDeliveryState are raced; pending steer wins over mailbox.
//  Turn items record on the caller CodexThread when a ThreadManager
//  is present.
//

import CodexCore
import CodexProtocol
import Foundation

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

func waitForV2Activity(
    delivery: AgentDeliveryState,
    threadId: ThreadId,
    inputQueue: InputQueue?,
    hasPendingSteer: Bool,
    timeout: Duration
) async -> WaitOutcome {
    let deliveryStream = delivery.subscribeActivity(threadId)
    let queueSubscription = inputQueue.map {
        $0.subscribeActivity(hasPendingSteer: hasPendingSteer)
    }
    if hasPendingSteer
        || queueSubscription?.1 == .steer
        || delivery.pendingActivity(threadId) == .steer {
        return .steered
    }
    if queueSubscription?.1 == .mailbox || delivery.pendingActivity(threadId) == .mailbox {
        return .mailboxActivity
    }
    return await withTaskGroup(of: WaitOutcome.self) { group in
        group.addTask {
            for await activity in deliveryStream {
                return activity == .steer ? .steered : .mailboxActivity
            }
            return .timedOut
        }
        if let queueStream = queueSubscription?.0 {
            group.addTask {
                for await activity in queueStream {
                    return activity == .steer ? .steered : .mailboxActivity
                }
                return .timedOut
            }
        }
        group.addTask {
            do {
                try await Task.sleep(for: timeout)
                return .timedOut
            } catch {
                return .timedOut
            }
        }
        let first = await group.next() ?? .timedOut
        group.cancelAll()
        while await group.next() != nil {}
        return first
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
        try? await control.emitTurnItemStarted(
            threadId: caller,
            turnId: invocation.turnId,
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: invocation.callId,
                    tool: .wait,
                    status: .inProgress,
                    senderThreadId: caller
                )
            )
        )
        let outcome = await waitForV2Activity(
            delivery: control.runtime.delivery,
            threadId: caller,
            inputQueue: invocation.inputQueue,
            hasPendingSteer: invocation.hasPendingSteer,
            timeout: .milliseconds(timeoutMs)
        )
        try? await control.emitTurnItemCompleted(
            threadId: caller,
            turnId: invocation.turnId,
            item: .collabAgentToolCall(
                CollabAgentToolCallItem(
                    id: invocation.callId,
                    tool: .wait,
                    status: .completed,
                    senderThreadId: caller
                )
            )
        )
        return WaitAgentV2Result.fromOutcome(
            outcome,
            requestedTimeoutMs: args.timeoutMs,
            timeoutMs: timeoutMs
        )
    }
}
