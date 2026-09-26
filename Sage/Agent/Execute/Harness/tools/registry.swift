//
//  registry.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/registry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Dispatch, exposure, and hook payload assembly. Pre/post hook execution
//  and Session services wait for Phase 5 / Phase 8.
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
}

extension CoreToolRuntime {
    func isBuiltinControlTool() -> Bool { false }
    func mcpServerName() -> String? { nil }
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
        guard let entry = entry(for: invocation.toolName) else {
            throw FunctionCallError.respondToModel(
                "unsupported tool \(flatToolName(invocation.toolName))"
            )
        }
        let result = try await entry.runtime.handle(invocation)
        return AnyToolResult(
            callId: invocation.callId,
            payload: invocation.payload,
            result: result,
            postToolUsePayload: PostToolUsePayload(
                toolName: HookToolName(flatToolName(invocation.toolName)),
                toolUseId: invocation.callId,
                toolInput: hookInput(invocation.payload),
                toolResponse: result.postToolUseResponse(callId: invocation.callId, payload: invocation.payload)
            )
        )
    }
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
