//
//  message_tool.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_v2/message_tool.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Shared V2 message argument parsing and mailbox send are live when
//  LocalAgentControl is attached.
//

import CodexCore
import CodexProtocol
import Foundation

struct SendMessageArgs: Decodable, Equatable, Sendable {
    var target: String
    var message: String
}

struct FollowupTaskArgs: Decodable, Equatable, Sendable {
    var target: String
    var message: String
}

func messageContent(_ message: String) throws -> String {
    if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw FunctionCallError.respondToModel("Empty message can't be sent to an agent")
    }
    return message
}

func resolveAgentTarget(_ invocation: ToolInvocation, target: String) async throws -> ThreadId {
    let control = try requireLocalAgentControl(invocation)
    let caller = try requireCallerThreadId(invocation)
    do {
        return try await control.resolve(
            caller: caller,
            parent: invocation.parentThreadId,
            source: invocation.sessionSource,
            target: target
        )
    } catch let err as CodexErr {
        throw collabV2AgentError(agentId: caller, err: err)
    }
}

func handleMessageStringTool(
    invocation: ToolInvocation,
    mode: MessageDeliveryMode,
    target: String,
    message: String
) async throws -> FunctionToolOutput {
    let message = try messageContent(message)
    let control = try requireLocalAgentControl(invocation)
    let caller = try requireCallerThreadId(invocation)
    let receiver = try await resolveAgentTarget(invocation, target: target)
    do {
        _ = try await control.send(
            SendRequest(
                caller: caller,
                target: .id(receiver),
                input: .message(message: .plaintext(message), mode: mode),
                startOptions: TurnStartOptions(
                    parentTurnId: mode == .triggerTurn ? invocation.turnId : nil
                )
            )
        )
    } catch let err as CodexErr {
        throw collabV2AgentError(agentId: receiver, err: err)
    }
    guard control.getAgentMetadata(receiver)?.agentPath != nil else {
        throw FunctionCallError.respondToModel("target agent is missing an agent_path")
    }
    return FunctionToolOutput.fromText("", success: true)
}

struct MessageTool {
    static func parseTarget(_ arguments: String) throws -> String {
        struct Args: Decodable {
            var target: String
        }
        let args: Args = try parseArguments(arguments)
        return args.target
    }
}
