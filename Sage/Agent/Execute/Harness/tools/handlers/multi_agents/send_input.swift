//
//  send_input.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents/send_input.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Spec, argument parsing, and mailbox send are live when
//  LocalAgentControl is attached. Session turn start is still pending.
//

import CodexCore
import CodexProtocol

struct SendInputArgs: Decodable, Equatable, Sendable {
    var target: String
    var message: String?
    var items: [UserInput]?
    var interrupt: Bool

    enum CodingKeys: String, CodingKey {
        case target, message, items, interrupt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        items = try container.decodeIfPresent([UserInput].self, forKey: .items)
        interrupt = try container.decodeIfPresent(Bool.self, forKey: .interrupt) ?? false
    }
}

struct SendInputResult: Encodable, Equatable, Sendable, ToolOutput {
    var submissionId: String

    enum CodingKeys: String, CodingKey {
        case submissionId = "submission_id"
    }

    func logOutput() -> String { toolOutputJsonText(self, toolName: "send_input") }
    func successForLogging() -> Bool { true }
    func toResponseItem(callId: String, payload: ToolPayload) -> ResponseInputItem {
        toolOutputResponseItem(
            callId: callId, payload: payload, value: self, success: true, toolName: "send_input")
    }
    func codeModeResult(_ payload: ToolPayload) -> HarnessJSON {
        toolOutputCodeModeResult(self, toolName: "send_input")
    }
}

struct SendInputHandler: CoreToolRuntime {
    func toolName() -> ToolName { ToolName(namespaced: MULTI_AGENT_V1_NAMESPACE, name: "send_input") }
    func spec() -> ToolSpec { createSendInputToolV1() }
    func searchInfo() -> ToolSearchInfo? {
        multiAgentToolSearchInfo(
            searchText:
                "send_input send message existing agent subagent follow up interrupt redirect queue target",
            spec: spec()
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        let arguments = try functionArguments(invocation.payload)
        let args: SendInputArgs = try parseArguments(arguments)
        let receiver = try parseAgentIdTarget(args.target)
        let items = try parseCollabInput(message: args.message, items: args.items)
        let control = try requireLocalAgentControl(invocation)
        let caller = try requireCallerThreadId(invocation)
        if args.interrupt {
            do {
                _ = try await control.interrupt(caller: caller, target: .id(receiver), version: .v1)
            } catch let err as CodexErr {
                throw collabAgentError(agentId: receiver, err: err)
            }
        }
        do {
            let receipt = try await control.send(
                SendRequest(
                    caller: caller,
                    target: .id(receiver),
                    input: .userInput(items),
                    startOptions: TurnStartOptions()
                )
            )
            return SendInputResult(submissionId: receipt.submissionId)
        } catch let err as CodexErr {
            throw collabAgentError(agentId: receiver, err: err)
        }
    }
}
