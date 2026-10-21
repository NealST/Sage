//
//  sage_execute.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  One handler per Sage execute tool. Dispatch forwards through
//  Session.services.onSageToolCall, the same seam MCP uses for onMcpCall.
//  Spec registration carries the real app schemas so the router — not a
//  responses-tools bypass — is the single tool assembly point.
//

import SageCore
import SageProtocol
import Foundation

/// A Sage execute tool with its real JSON Schema, converted from the app
/// `ToolDefinition` by `ExecuteHarnessAttach.sageToolSpecs`.
struct SageToolSpec: Equatable, Sendable {
    var name: String
    var description: String
    var parameters: JsonSchema
}

struct SageExecuteHandler: CoreToolRuntime {
    var name: ToolName
    var toolSpec: ToolSpec

    init(spec: SageToolSpec) {
        let toolName = ToolName(plain: spec.name)
        self.name = toolName
        self.toolSpec = .function(
            ResponsesApiTool(
                name: spec.name,
                description: spec.description.isEmpty ? spec.name : spec.description,
                strict: false,
                parameters: spec.parameters
            )
        )
    }

    func toolName() -> ToolName { name }
    func spec() -> ToolSpec { toolSpec }

    func supportsParallelToolCalls() -> Bool {
        ParallelToolRuntime.supportsParallel(flatToolName(name))
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "\(flatToolName(name)) handler received unsupported payload"
            )
        }
        guard let onSage = invocation.onSageToolCall else {
            throw FunctionCallError.respondToModel(
                "\(flatToolName(name)) is not wired (Sage execute)"
            )
        }
        guard let output = await onSage(flatToolName(name), invocation.callId, arguments) else {
            throw FunctionCallError.respondToModel(
                "\(flatToolName(name)) was cancelled before receiving a response"
            )
        }
        return boxedToolOutput(FunctionToolOutput.fromText(output, success: !output.hasPrefix("ERROR:")))
    }
}

func registerSageTools(_ specs: [SageToolSpec], on router: inout ToolRouter) {
    var existing = Set(router.registry.registeredEntries().map { flatToolName($0.runtime.toolName()) })
    existing.formUnion(router.modelVisibleSpecs.map { $0.name() })
    for spec in specs {
        guard !existing.contains(spec.name) else { continue }
        existing.insert(spec.name)
        let handler = SageExecuteHandler(spec: spec)
        router.registry.register(handler)
        router.modelVisibleSpecs.append(handler.spec())
    }
}
