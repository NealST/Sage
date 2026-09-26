//
//  dynamic.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/dynamic.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session pending-dynamic-tool channels wait for Phase 5. The handler
//  forwards through onDynamicTool.
//

import CodexCore
import CodexProtocol
import Foundation

func defaultNamespaceDescription(_ name: String) -> String {
    "Tools in the \(name) namespace."
}

func dynamicToolToResponsesApiTool(_ tool: DynamicToolFunctionSpec) -> ResponsesApiTool {
    let parameters: JsonSchema
    if let data = try? JSONEncoder().encode(tool.inputSchema),
       let schema = try? JSONDecoder().decode(JsonSchema.self, from: data) {
        parameters = schema
    } else {
        parameters = .object([:], additionalProperties: false)
    }
    return ResponsesApiTool(
        name: tool.name,
        description: tool.description,
        strict: false,
        parameters: parameters
    )
}

struct DynamicToolHandler: CoreToolRuntime {
    var name: ToolName
    var toolSpec: ToolSpec
    var toolExposure: ToolExposure

    init?(_ tool: DynamicToolFunctionSpec, namespace: DynamicToolNamespaceSpec? = nil) {
        name = ToolName(namespace: namespace?.name, name: tool.name)
        var output = dynamicToolToResponsesApiTool(tool)
        if let namespace {
            let description = namespace.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? defaultNamespaceDescription(namespace.name)
                : namespace.description
            toolSpec = .namespace(
                ResponsesApiNamespace(
                    name: namespace.name,
                    description: description,
                    tools: [ResponsesApiNamespaceTool(function: output)]
                )
            )
        } else {
            toolSpec = .function(output)
        }
        toolExposure = tool.deferLoading ? .deferred : .direct
    }

    func toolName() -> ToolName { name }
    func spec() -> ToolSpec { toolSpec }
    func exposure() -> ToolExposure { toolExposure }
    func searchInfo() -> ToolSearchInfo? {
        ToolSearchInfo(
            description: toolSpec.name(),
            keywords: [flatToolName(name)],
            source: ToolSearchSourceInfo(
                name: "Dynamic tools",
                description: "Tools provided by the current Codex thread."
            )
        )
    }

    func handle(_ invocation: ToolInvocation) async throws -> any ToolOutput {
        guard case .function(let arguments) = invocation.payload else {
            throw FunctionCallError.respondToModel(
                "dynamic tool handler received unsupported payload"
            )
        }
        let args: HarnessJSON
        if let data = arguments.data(using: .utf8),
           let value = try? JSONDecoder().decode(HarnessJSON.self, from: data) {
            args = value
        } else {
            args = .object([:])
        }
        guard let onDynamic = invocation.onDynamicTool else {
            throw FunctionCallError.respondToModel(
                "dynamic tool call is not wired (Phase 5 Session)"
            )
        }
        guard let response = await onDynamic(name, args) else {
            throw FunctionCallError.respondToModel(
                "dynamic tool call was cancelled before receiving a response"
            )
        }
        let body: [FunctionCallOutputContentItem] = response.contentItems.map { item in
            switch item {
            case .inputText(let text):
                return .inputText(text: text)
            case .inputImage(let imageUrl):
                return .inputText(text: imageUrl)
            case .inputAudio(let audioUrl):
                return .inputText(text: audioUrl)
            }
        }
        return boxedToolOutput(FunctionToolOutput.fromContent(body, success: response.success))
    }
}
