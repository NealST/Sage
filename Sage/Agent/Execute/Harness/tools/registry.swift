//
//  registry.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/registry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Dispatch, exposure, and hook payload assembly. `dispatch` runs rust's
//  PreToolUse → handle → PostToolUse sandwich through `HookRuntime`.
//

import CodexCore
import CodexProtocol
import Foundation

protocol ToolExecutor: Sendable {
    func toolName() -> ToolName
    func spec() -> ToolSpec
    func exposure() -> ToolExposure
    func searchInfo() -> ToolSearchInfo?
    func supportsParallelToolCalls() -> Bool
    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput
}

extension ToolExecutor {
    func exposure() -> ToolExposure { .direct }
    func searchInfo() -> ToolSearchInfo? { nil }
    func supportsParallelToolCalls() -> Bool { false }
}

protocol CoreToolRuntime: ToolExecutor {
    func isBuiltinControlTool() -> Bool
    func mcpServerName() -> String?
    func createDiffConsumer() -> (any ToolArgumentDiffConsumer)?
}

extension CoreToolRuntime {
    func isBuiltinControlTool() -> Bool { false }
    func mcpServerName() -> String? { nil }
    func createDiffConsumer() -> (any ToolArgumentDiffConsumer)? { nil }
}

protocol ToolArgumentDiffConsumer: AnyObject {
    func consumeDiff(turn: TurnContext, callId: String, delta: String) -> EventMsg?
    func finish() throws -> EventMsg?
}

struct ToolRegistryEntry {
    var runtime: any CoreToolRuntime
    var exposure: ToolExposure
}

struct AnyToolResult {
    var callId: String
    var payload: ToolPayload
    var result: any ToolOutput
    var postToolUsePayload: PostToolUsePayload?
}

struct PostToolUsePayload: Equatable, Sendable {
    var toolName: HookToolName
    var toolUseId: String
    var toolInput: HarnessJSON
    var toolResponse: HarnessJSON?
}

struct HarnessToolRegistry {
    private var entries: [String: ToolRegistryEntry] = [:]

    mutating func register(_ runtime: any CoreToolRuntime, exposure: ToolExposure? = nil) {
        let name = flatToolName(runtime.toolName())
        entries[name] = ToolRegistryEntry(
            runtime: runtime,
            exposure: exposure ?? runtime.exposure()
        )
    }

    func entry(for toolName: ToolName) -> ToolRegistryEntry? {
        entries[flatToolName(toolName)] ?? entries[toolName.name]
    }

    func registeredEntries() -> [ToolRegistryEntry] {
        entries.values.sorted { flatToolName($0.runtime.toolName()) < flatToolName($1.runtime.toolName()) }
    }

    func dispatch(_ invocation: ToolInvocation) async throws -> AnyToolResult {
        var invocation = invocation
        let toolName = flatToolName(invocation.toolName)
        if let projectRoot = invocation.hookProjectRoot {
            let command = hookCommand(invocation.payload)
            let pre = await HookRuntime.preToolUse(
                tool: toolName,
                command: command,
                projectRoot: projectRoot,
                argumentsJSON: command,
                activatedSkills: invocation.hookActivatedSkills,
                sessionId: invocation.threadId?.description ?? "",
                turnId: invocation.turnId,
                cwd: projectRoot.path,
                model: invocation.hookModel,
                permissionMode: invocation.hookPermissionMode,
                toolUseId: invocation.callId
            )
            invocation.onAdditionalContexts?(pre.additionalContexts)
            if pre.shouldStop {
                throw FunctionCallError.respondToModel(
                    preToolUseBlockMessage(
                        toolName: toolName,
                        reason: pre.additionalContexts.first ?? "Hook denied this tool.",
                        payload: invocation.payload
                    )
                )
            }
            if let updated = pre.updatedInput, case .function = invocation.payload {
                invocation.payload = .function(arguments: updated)
            }
        }

        var result = try await handleRegisteredOrSage(invocation)
        let success = result.result.successForLogging()
        guard success, let projectRoot = invocation.hookProjectRoot else {
            return result
        }

        let post = await HookRuntime.postToolUse(
            tool: toolName,
            projectRoot: projectRoot,
            argumentsJSON: hookCommand(invocation.payload),
            activatedSkills: invocation.hookActivatedSkills,
            sessionId: invocation.threadId?.description ?? "",
            turnId: invocation.turnId,
            cwd: projectRoot.path,
            model: invocation.hookModel,
            permissionMode: invocation.hookPermissionMode,
            toolUseId: invocation.callId,
            toolResponse: result.result.logOutput()
        )
        invocation.onAdditionalContexts?(post.additionalContexts)
        if post.shouldStop {
            throw FunctionCallError.respondToModel(
                post.additionalContexts.first ?? "PostToolUse hook blocked the tool result"
            )
        }
        if let feedback = post.feedbackMessage, !feedback.isEmpty {
            result.result = PostToolUseFeedbackOutput(
                original: result.result,
                modelVisible: FunctionToolOutput.fromText(feedback, success: nil)
            )
        }
        return result
    }

    private func handleRegisteredOrSage(_ invocation: ToolInvocation) async throws -> AnyToolResult {
        if let entry = entry(for: invocation.toolName) {
            let result = try await entry.runtime.handle(invocation)
            return makeToolResult(invocation: invocation, result: result)
        }
        if let onSage = invocation.onSageToolCall,
           case .function(let arguments) = invocation.payload,
           let output = await onSage(flatToolName(invocation.toolName), invocation.callId, arguments) {
            let result = boxedToolOutput(
                FunctionToolOutput.fromText(output, success: !output.hasPrefix("ERROR:"))
            )
            return makeToolResult(invocation: invocation, result: result)
        }
        throw FunctionCallError.respondToModel(
            "unsupported tool \(flatToolName(invocation.toolName))"
        )
    }
}

private func makeToolResult(invocation: ToolInvocation, result: any ToolOutput) -> AnyToolResult {
    AnyToolResult(
        callId: invocation.callId,
        payload: invocation.payload,
        result: result,
        postToolUsePayload: PostToolUsePayload(
            toolName: HookToolName(flatToolName(invocation.toolName)),
            toolUseId: invocation.callId,
            toolInput: hookInput(invocation.payload),
            toolResponse: result.postToolUseResponse(
                callId: invocation.callId,
                payload: invocation.payload
            )
        )
    )
}

func hookCommand(_ payload: ToolPayload) -> String? {
    switch payload {
    case .function(let arguments):
        return arguments
    case .toolSearch(let arguments):
        return arguments.query
    case .custom(let input):
        return input
    }
}

func preToolUseBlockMessage(toolName: String, reason: String, payload: ToolPayload) -> String {
    if (toolName == "Bash" || toolName == "apply_patch" || toolName == "run_shell_command"),
       case .function(let arguments) = payload,
       let data = arguments.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let command = object["command"] as? String {
        return "Command blocked by PreToolUse hook: \(reason). Command: \(command)"
    }
    return "Tool call blocked by PreToolUse hook: \(reason). Tool: \(toolName)"
}

func hookInput(_ payload: ToolPayload) -> HarnessJSON {
    switch payload {
    case .function(let arguments):
        if let data = arguments.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return jsonValue(from: object)
        }
        return .string(arguments)
    case .toolSearch(let arguments):
        return .object(["query": .string(arguments.query)])
    case .custom(let input):
        return .string(input)
    }
}

func jsonValue(from object: Any) -> HarnessJSON {
    switch object {
    case let value as String: return .string(value)
    case let value as Bool: return .bool(value)
    case let value as Int: return .int(Int64(value))
    case let value as Int64: return .int(value)
    case let value as Double: return .double(value)
    case let value as [Any]: return .array(value.map(jsonValue(from:)))
    case let value as [String: Any]:
        return .object(value.mapValues(jsonValue(from:)))
    case is NSNull:
        return .null
    default:
        return .string(String(describing: object))
    }
}
