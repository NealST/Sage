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
    let textContent: String?
    let contentParts: [APIContentPart]?
    let toolCallID: String?
    let toolCalls: [APIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    private struct Payload {
        var textContent: String?
        var contentParts: [APIContentPart]?
        var toolCalls: [APIToolCall]?
    }

    init(_ event: AgentEvent, includeImageParts: Bool = false) {
        role = Self.role(for: event.kind)
        let payload = Self.payload(for: event, includeImageParts: includeImageParts)
        textContent = payload.textContent
        contentParts = payload.contentParts
        toolCalls = payload.toolCalls
        toolCallID = event.toolCallID
    }

    private static func role(for kind: AgentEventKind) -> String {
        switch kind {
        case .systemInstruction:
            return "system"

        case .userInput:
            return "user"

        case .assistantResponse:
            return "assistant"

        case .toolResult:
            return "tool"
        }
    }

    private static func payload(
        for event: AgentEvent,
        includeImageParts: Bool
    ) -> Payload {
        if let toolCalls = event.toolCalls, !toolCalls.isEmpty {
            return Payload(
                textContent: event.content.isEmpty ? nil : event.content,
                contentParts: nil,
                toolCalls: toolCalls.map { call in
                    APIToolCall(
                        id: call.id,
                        type: "function",
                        function: APIToolCallFunction(name: call.name, arguments: call.argumentsJSON)
                    )
                }
            )
        }
        return contentPayload(for: event, includeImageParts: includeImageParts)
    }

    private static func contentPayload(
        for event: AgentEvent,
        includeImageParts: Bool
    ) -> Payload {
        // Strip write-file diff sidecars — keep model context lean.
        var text = event.kind == .toolResult
            ? WriteFileResultCodec.modelFacing(event.content)
            : event.content
        let images: [APIContentPart]
        if includeImageParts, event.kind == .userInput {
            let encoded = encodedImages(from: event.attachments)
            images = encoded.parts
            if !encoded.unavailable.isEmpty {
                let names = encoded.unavailable.joined(separator: ", ")
                let notice = "[Vision unavailable for: \(names)]"
                text = text.isEmpty ? notice : text + "\n\n" + notice
            }
        } else {
            images = []
        }
        guard !images.isEmpty else {
            return Payload(textContent: text, contentParts: nil, toolCalls: nil)
        }
        var parts: [APIContentPart] = []
        if !text.isEmpty {
            parts.append(.text(text))
        }
        parts.append(contentsOf: images)
        return Payload(textContent: nil, contentParts: parts, toolCalls: nil)
    }

    private static func encodedImages(
        from attachments: [MessageAttachment]
    ) -> (parts: [APIContentPart], unavailable: [String]) {
        var parts: [APIContentPart] = []
        var unavailable: [String] = []
        for item in attachments where item.kind == .image {
            if let url = AttachmentImageEncoder.dataURL(for: item.fileURL) {
                parts.append(.image(url: url))
            } else {
                unavailable.append(item.displayName)
            }
        }
        return (parts, unavailable)
    }

    static func messages(from events: [AgentEvent]) -> [Self] {
        let latestUserID = events.last { $0.kind == .userInput }?.id
        return events.map { event in
            Self(event, includeImageParts: event.id == latestUserID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let contentParts {
            try container.encode(contentParts, forKey: .content)
        } else {
            try container.encodeIfPresent(textContent, forKey: .content)
        }
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
    }
}

nonisolated struct APIContentPart: Encodable, Sendable, Equatable {
    var type: String
    var text: String?
    var imageURL: APIImageURL?

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    static func text(_ text: String) -> Self {
        Self(type: "text", text: text, imageURL: nil)
    }

    static func image(url: String) -> Self {
        Self(type: "image_url", text: nil, imageURL: APIImageURL(url: url))
    }
}

nonisolated struct APIImageURL: Encodable, Sendable, Equatable {
    var url: String
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
    let reasoning: String?
    let reasoningContent: String?
    let thinking: String?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
        case reasoning
        case reasoningContent = "reasoning_content"
        case thinking
    }

    var thinkingText: String? {
        [reasoningContent, reasoning, thinking]
            .compactMap { $0 }
            .first { !$0.isEmpty }
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
