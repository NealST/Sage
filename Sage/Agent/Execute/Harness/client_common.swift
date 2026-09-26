//
//  client_common.swift
//  CodexCore
//
//  Port of codex-rs/core/src/client_common.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Re-exports CodexAPI.ResponseEvent. Prompt.tools is pre-serialized
//  JSON (Sage ToolSpec lives in the app module). ResponseStream is an
//  AsyncStream; dropping the stream cancels via Task.
//

import CodexAPI
import CodexAsyncUtils
import CodexProtocol
import Foundation

public typealias ResponseEvent = CodexAPI.ResponseEvent

public struct Prompt: Sendable {
    public var input: [ResponseItem]
    public var tools: [JSONValue]
    public var parallelToolCalls: Bool
    public var baseInstructions: BaseInstructions
    public var outputSchema: JSONValue?
    public var outputSchemaStrict: Bool
    public var cyberAccessProgram: CyberAccessProgram?

    public init(
        input: [ResponseItem] = [],
        tools: [JSONValue] = [],
        parallelToolCalls: Bool = false,
        baseInstructions: BaseInstructions = BaseInstructions(),
        outputSchema: JSONValue? = nil,
        outputSchemaStrict: Bool = true,
        cyberAccessProgram: CyberAccessProgram? = nil
    ) {
        self.input = input
        self.tools = tools
        self.parallelToolCalls = parallelToolCalls
        self.baseInstructions = baseInstructions
        self.outputSchema = outputSchema
        self.outputSchemaStrict = outputSchemaStrict
        self.cyberAccessProgram = cyberAccessProgram
    }

    public func getFormattedInputForRequest(modelInfo: ModelInfo) -> [ResponseItem] {
        var input = self.input
        normalizeImageDetails(&input, modelInfo: modelInfo)
        return input
    }
}

func normalizeImageDetails(_ items: inout [ResponseItem], modelInfo: ModelInfo) {
    for index in items.indices {
        switch items[index] {
        case .message(let id, let role, var content, let phase, let meta):
            for contentIndex in content.indices {
                if case .inputImage(let image, var detail) = content[contentIndex] {
                    normalizeImageDetail(&detail, modelInfo: modelInfo)
                    content[contentIndex] = .inputImage(image: image, detail: detail)
                }
            }
            items[index] = .message(
                id: id, role: role, content: content, phase: phase,
                internalChatMessageMetadataPassthrough: meta)
        case .functionCallOutput(let id, let callId, let name, let namespace, var output, let meta):
            normalizePayloadImageDetails(&output, modelInfo: modelInfo)
            items[index] = .functionCallOutput(
                id: id, callId: callId, name: name, namespace: namespace,
                output: output, internalChatMessageMetadataPassthrough: meta)
        case .customToolCallOutput(let id, let callId, let name, var output, let meta):
            normalizePayloadImageDetails(&output, modelInfo: modelInfo)
            items[index] = .customToolCallOutput(
                id: id, callId: callId, name: name, output: output,
                internalChatMessageMetadataPassthrough: meta)
        default:
            break
        }
    }
}

func normalizePayloadImageDetails(_ output: inout FunctionCallOutputPayload, modelInfo: ModelInfo) {
    guard case .contentItems(var items) = output.body else { return }
    for index in items.indices {
        if case .inputImage(let image, var detail) = items[index] {
            normalizeImageDetail(&detail, modelInfo: modelInfo)
            items[index] = .inputImage(image: image, detail: detail)
        }
    }
    output.body = .contentItems(items)
}

func normalizeImageDetail(_ detail: inout ImageDetail?, modelInfo: ModelInfo) {
    if modelInfo.useResponsesLite {
        detail = nil
    } else if detail == .original && !modelInfo.supportsImageDetailOriginal {
        detail = defaultImageDetail
    }
}

public struct ResponseStream: Sendable {
    public var events: AsyncStream<CodexResult<ResponseEvent>>
    public var consumerDropped: CancellationToken
    public var upstreamRequestId: String?

    public init(
        events: AsyncStream<CodexResult<ResponseEvent>>,
        consumerDropped: CancellationToken = CancellationToken(),
        upstreamRequestId: String? = nil
    ) {
        self.events = events
        self.consumerDropped = consumerDropped
        self.upstreamRequestId = upstreamRequestId
    }
}
