//
//  multi_agents_common.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/multi_agents_common.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Telemetry emit for spawn failure is a no-op until SessionTelemetry
//  exists.
//

import CodexCore
import CodexProtocol
import Foundation

let MIN_WAIT_TIMEOUT_MS = DEFAULT_MULTI_AGENT_V2_MIN_WAIT_TIMEOUT_MS
let DEFAULT_WAIT_TIMEOUT_MS = DEFAULT_MULTI_AGENT_V2_DEFAULT_WAIT_TIMEOUT_MS
let MAX_WAIT_TIMEOUT_MS = HARD_MAX_MULTI_AGENT_V2_TIMEOUT_MS

func functionArguments(_ payload: ToolPayload) throws -> String {
    guard case .function(let arguments) = payload else {
        throw FunctionCallError.respondToModel("collab handler received unsupported payload")
    }
    return arguments
}

func toolOutputJsonText<T: Encodable>(_ value: T, toolName: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        return text
    }
    return HarnessJSON.string("failed to serialize \(toolName) result").encodedString()
}

func toolOutputResponseItem<T: Encodable>(
    callId: String,
    payload: ToolPayload,
    value: T,
    success: Bool?,
    toolName: String
) -> ResponseInputItem {
    FunctionToolOutput.fromText(toolOutputJsonText(value, toolName: toolName), success: success)
        .toResponseItem(callId: callId, payload: payload)
}

func toolOutputCodeModeResult<T: Encodable>(_ value: T, toolName: String) -> HarnessJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(value),
       let parsed = try? JSONDecoder().decode(HarnessJSON.self, from: data)
    {
        return parsed
    }
    return .string("failed to serialize \(toolName) result")
}

func collabSpawnError(_ err: CodexErr) -> FunctionCallError {
    switch err.detailsValue() {
    case .unsupportedOperation(let message) where message == "thread manager dropped":
        return .respondToModel("collab manager unavailable")
    case .unsupportedOperation(let message):
        return .respondToModel(message)
    default:
        return .respondToModel("collab spawn failed: \(err)")
    }
}

func recordCollabSpawnFailure(
    err: CodexErr,
    forkMode: SpawnAgentForkMode?,
    multiAgentVersion: MultiAgentVersion
) {
    _ = collabSpawnFailureReason(err)
    _ = forkMode
    _ = multiAgentVersion
}

func collabSpawnFailureReason(_ err: CodexErr) -> String {
    switch err.detailsValue() {
    case .agentLimitReached: return "limit_reached"
    case .invalidRequest: return "invalid_request"
    case .threadNotFound: return "thread_not_found"
    case .unsupportedOperation: return "unsupported_operation"
    default: return "internal"
    }
}

func collabAgentError(agentId: ThreadId, err: CodexErr) -> FunctionCallError {
    switch err.detailsValue() {
    case .threadNotFound(let id):
        return .respondToModel("agent with id \(id) not found")
    case .internalAgentDied:
        return .respondToModel("agent with id \(agentId) is closed")
    case .unsupportedOperation:
        return .respondToModel("collab manager unavailable")
    default:
        return .respondToModel("collab tool failed: \(err)")
    }
}

func collabV2AgentError(agentId: ThreadId, err: CodexErr) -> FunctionCallError {
    switch err.detailsValue() {
    case .unsupportedOperation(let message) where message != "thread manager dropped":
        return .respondToModel(message)
    default:
        return collabAgentError(agentId: agentId, err: err)
    }
}

func threadSpawnSource(
    parentThreadId: ThreadId,
    parentSessionSource: SessionSource,
    depth: Int32,
    agentRole: String?,
    taskName: String?
) throws -> SessionSource {
    let agentPath: AgentPath?
    if let taskName {
        do {
            agentPath = try (parentSessionSource.getAgentPath() ?? .root()).join(taskName)
        } catch {
            throw FunctionCallError.respondToModel(String(describing: error))
        }
    } else {
        agentPath = nil
    }
    return .subAgent(
        .threadSpawn(
            parentThreadId: parentThreadId,
            depth: depth,
            agentPath: agentPath,
            agentNickname: nil,
            agentRole: agentRole
        )
    )
}

func requireLocalAgentControl(_ invocation: ToolInvocation) throws -> LocalAgentControl {
    guard let control = invocation.localAgentControl else {
        throw FunctionCallError.respondToModel("collab manager unavailable")
    }
    return control
}

func nonEmptyOrNil(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func requireCallerThreadId(_ invocation: ToolInvocation) throws -> ThreadId {
    guard let threadId = invocation.threadId else {
        throw FunctionCallError.respondToModel("collab manager unavailable")
    }
    return threadId
}

func clampWaitTimeoutMs(_ timeoutMs: Int64?) throws -> Int64 {
    let timeoutMs = timeoutMs ?? DEFAULT_WAIT_TIMEOUT_MS
    if timeoutMs <= 0 {
        throw FunctionCallError.respondToModel("timeout_ms must be greater than zero")
    }
    return min(max(timeoutMs, MIN_WAIT_TIMEOUT_MS), MAX_WAIT_TIMEOUT_MS)
}

func parseCollabInput(message: String?, items: [UserInput]?) throws -> [UserInput] {
    switch (message, items) {
    case (_?, _?):
        throw FunctionCallError.respondToModel("Provide either message or items, but not both")
    case (nil, nil):
        throw FunctionCallError.respondToModel("Provide one of: message or items")
    case (let message?, nil):
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FunctionCallError.respondToModel("Empty message can't be sent to an agent")
        }
        return [.text(text: message, textElements: [])]
    case (nil, let items?):
        if items.isEmpty {
            throw FunctionCallError.respondToModel("Items can't be empty")
        }
        return items
    }
}
