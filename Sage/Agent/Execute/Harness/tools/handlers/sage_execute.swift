//
//  sage_execute.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  One handler per Sage execute tool. Dispatch forwards through
//  Session.services.onSageToolCall, the same seam MCP uses for onMcpCall.
//

import CodexProtocol
import Foundation

struct SageExecuteHandler: CoreToolRuntime {
    var name: ToolName
    var toolSpec: ToolSpec

    init(name: String, description: String = "") {
        let toolName = ToolName(plain: name)
        self.name = toolName
        self.toolSpec = .function(
            ResponsesApiTool(
                name: name,
                description: description.isEmpty ? name : description,
                strict: false,
                parameters: .object([:], additionalProperties: true)
            )
        )
    }

    func toolName() -> ToolName { name }
    func spec() -> ToolSpec { toolSpec }

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

func registerSageTools(_ names: [String], on router: inout ToolRouter) {
    var existing = Set(router.registry.registeredEntries().map { flatToolName($0.runtime.toolName()) })
    existing.formUnion(router.modelVisibleSpecs.map { $0.name() })
    for name in names {
        guard !existing.contains(name) else { continue }
        existing.insert(name)
        let handler = SageExecuteHandler(name: name)
        router.registry.register(handler)
        router.modelVisibleSpecs.append(handler.spec())
    }
}
