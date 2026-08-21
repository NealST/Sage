//
//  ModelClientWire.swift
//  Sage
//
//  OpenAI-compatible request/response DTOs for ModelClient.
//

import Foundation

nonisolated struct ChatCompletionStreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

nonisolated struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let tools: [APITool]?
    let toolChoice: String?
    let temperature: Double?
    let stream: Bool?
    let streamOptions: ChatCompletionStreamOptions?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, temperature
        case toolChoice = "tool_choice"
        case streamOptions = "stream_options"
    }

    init(
        model: String,
        messages: [APIMessage],
        tools: [APITool]?,
        toolChoice: String?,
        temperature: Double? = nil,
        stream: Bool? = nil,
        streamOptions: ChatCompletionStreamOptions? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.temperature = temperature
        self.stream = stream
        self.streamOptions = streamOptions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(stream, forKey: .stream)
        try container.encodeIfPresent(streamOptions, forKey: .streamOptions)
    }
}

nonisolated struct APIMessage: Encodable {
    let role: String
    let content: String?
    let toolCallID: String?
    let toolCalls: [APIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    init(_ event: AgentEvent) {
        switch event.kind {
        case .systemInstruction: role = "system"
        case .userInput: role = "user"
        case .assistantResponse: role = "assistant"
        case .toolResult: role = "tool"
        }
        // OpenAI wants content null (or omitted) when tool_calls are present sometimes;
        // empty string is widely accepted by compatible providers.
        if let toolCalls = event.toolCalls, !toolCalls.isEmpty {
            content = event.content.isEmpty ? nil : event.content
            self.toolCalls = toolCalls.map { call in
                APIToolCall(
                    id: call.id,
                    type: "function",
                    function: APIToolCallFunction(name: call.name, arguments: call.argumentsJSON)
                )
            }
        } else {
            // Strip write-file diff sidecars — keep model context lean.
            content = event.kind == .toolResult
                ? WriteFileResultCodec.modelFacing(event.content)
                : event.content
            self.toolCalls = nil
        }
        toolCallID = event.toolCallID
    }
}

nonisolated struct APIToolCall: Encodable {
    let id: String
    let type: String
    let function: APIToolCallFunction
}

nonisolated struct APIToolCallFunction: Encodable {
    let name: String
    let arguments: String
}

nonisolated struct APITool: Encodable {
    let type = "function"
    let function: APIFunction

    init(_ tool: ToolDefinition) {
        function = APIFunction(
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters
        )
    }
}

nonisolated struct APIFunction: Encodable {
    let name: String
    let description: String
    let parameters: JSONValue
}

nonisolated struct APIUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

nonisolated struct ChatCompletionChoiceMessage: Decodable {
    let content: String?
    let toolCalls: [ChatCompletionToolCall]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

nonisolated struct ChatCompletionToolCallFunction: Decodable {
    let name: String
    let arguments: String
}

nonisolated struct ChatCompletionToolCall: Decodable {
    let id: String
    let function: ChatCompletionToolCallFunction
}

nonisolated struct ChatCompletionChoice: Decodable {
    let message: ChatCompletionChoiceMessage
}

nonisolated struct ChatCompletionResponse: Decodable {
    let choices: [ChatCompletionChoice]
    let usage: APIUsage?
}

// MARK: - Streaming wire format

nonisolated struct StreamingFunctionDelta: Decodable {
    let name: String?
    let arguments: String?
}

nonisolated struct StreamingToolCallDelta: Decodable {
    let index: Int
    let id: String?
    let function: StreamingFunctionDelta?
}

nonisolated struct StreamingDelta: Decodable {
    let content: String?
    let toolCalls: [StreamingToolCallDelta]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

nonisolated struct StreamingChoice: Decodable {
    let delta: StreamingDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

nonisolated struct StreamingChunk: Decodable {
    let choices: [StreamingChoice]
    let usage: APIUsage?
}
