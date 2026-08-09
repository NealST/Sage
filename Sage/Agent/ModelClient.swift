//
//  ModelClient.swift
//  Sage
//

import Foundation

struct ToolCallProposal: Sendable, Equatable {
    let id: String
    let name: String
    let argumentsJSON: String
}

struct ModelTurn: Sendable {
    let content: String?
    let toolCalls: [ToolCallProposal]
}

// MARK: - Streaming types

/// A single incremental chunk from the SSE stream.
enum StreamDelta: Sendable {
    /// A text content fragment.
    case text(String)
    /// A tool call fragment (index identifies which call is being built).
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String?)
    /// The stream has finished; includes the stop reason.
    case done
}

enum ModelClientError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpStatus(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add an API key in Settings before asking Sage."
        case .invalidURL:
            return "Model base URL is invalid."
        case .httpStatus(let code, let body):
            return "Model API error (\(code)): \(body)"
        case .decoding(let detail):
            return "Could not parse model response: \(detail)"
        }
    }
}

actor ModelClient {
    /// Lightweight connectivity check against an OpenAI-compatible provider.
    func probe(settings: ModelSettingsSnapshot) async throws {
        guard !settings.apiKey.isEmpty else { throw ModelClientError.notConfigured }

        let trimmedBase = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let modelsURL = URL(string: "\(trimmedBase)/models") else {
            throw ModelClientError.invalidURL
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelClientError.httpStatus(-1, "No HTTP response")
        }

        // Some gateways omit `/models`; fall back to a tiny completion.
        if http.statusCode == 404 {
            _ = try await complete(
                events: [AgentEvent(kind: .userInput, content: "ping")],
                tools: [],
                settings: settings
            )
            return
        }

        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ModelClientError.httpStatus(http.statusCode, text)
        }
    }

    /// Streaming variant — returns an `AsyncThrowingStream` of incremental deltas.
    /// The caller accumulates text and tool call fragments, then assembles the final `ModelTurn`.
    func streamComplete(
        events: [AgentEvent],
        tools: [ToolDefinition],
        settings: ModelSettingsSnapshot
    ) async throws -> AsyncThrowingStream<StreamDelta, Error> {
        guard !settings.apiKey.isEmpty else { throw ModelClientError.notConfigured }

        let trimmedBase = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            throw ModelClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body = StreamingChatCompletionRequest(
            model: settings.model,
            messages: events.map(APIMessage.init),
            tools: tools.isEmpty ? nil : tools.map(APITool.init),
            toolChoice: tools.isEmpty ? nil : "auto",
            stream: true
        )
        request.httpBody = try JSONEncoder().encode(body)

        try Task.checkCancellation()
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw ModelClientError.httpStatus(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Read the error body from the byte stream
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let text = String(data: errorData, encoding: .utf8) ?? ""
            throw ModelClientError.httpStatus(http.statusCode, text)
        }

        return AsyncThrowingStream { continuation in
            let parseTask = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()

                        // SSE format: lines starting with "data: "
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamingChunk.self, from: data)
                        else { continue }

                        guard let delta = chunk.choices.first?.delta else { continue }

                        // Text content delta
                        if let content = delta.content, !content.isEmpty {
                            continuation.yield(.text(content))
                        }

                        // Tool call deltas
                        if let toolCalls = delta.toolCalls {
                            for tc in toolCalls {
                                continuation.yield(.toolCallDelta(
                                    index: tc.index,
                                    id: tc.id,
                                    name: tc.function?.name,
                                    arguments: tc.function?.arguments
                                ))
                            }
                        }
                    }
                    // Stream ended without [DONE] — still finish gracefully
                    continuation.yield(.done)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                parseTask.cancel()
            }
        }
    }

    func complete(
        events: [AgentEvent],
        tools: [ToolDefinition],
        settings: ModelSettingsSnapshot
    ) async throws -> ModelTurn {
        guard !settings.apiKey.isEmpty else { throw ModelClientError.notConfigured }

        let trimmedBase = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            throw ModelClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let body = ChatCompletionRequest(
            model: settings.model,
            messages: events.map(APIMessage.init),
            tools: tools.isEmpty ? nil : tools.map(APITool.init),
            toolChoice: tools.isEmpty ? nil : "auto"
        )
        request.httpBody = try JSONEncoder().encode(body)

        try Task.checkCancellation()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse else {
            throw ModelClientError.httpStatus(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ModelClientError.httpStatus(http.statusCode, text)
        }

        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let choice = decoded.choices.first?.message
            let toolCalls = (choice?.toolCalls ?? []).map {
                ToolCallProposal(
                    id: $0.id,
                    name: $0.function.name,
                    argumentsJSON: $0.function.arguments
                )
            }
            return ModelTurn(content: choice?.content, toolCalls: toolCalls)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ModelClientError.decoding(error.localizedDescription)
        }
    }
}

nonisolated struct ModelSettingsSnapshot: Sendable {
    let baseURL: String
    let model: String
    let apiKey: String
}

// MARK: - Wire format

nonisolated private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let tools: [APITool]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools
        case toolChoice = "tool_choice"
    }
}

nonisolated private struct APIMessage: Encodable {
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
            self.toolCalls = toolCalls.map {
                APIToolCall(
                    id: $0.id,
                    type: "function",
                    function: APIToolCallFunction(name: $0.name, arguments: $0.argumentsJSON)
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

nonisolated private struct APIToolCall: Encodable {
    let id: String
    let type: String
    let function: APIToolCallFunction
}

nonisolated private struct APIToolCallFunction: Encodable {
    let name: String
    let arguments: String
}

nonisolated private struct APITool: Encodable {
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

nonisolated private struct APIFunction: Encodable {
    let name: String
    let description: String
    let parameters: JSONValue
}

nonisolated private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        let id: String
        let function: Function

        struct Function: Decodable {
            let name: String
            let arguments: String
        }
    }
}

// MARK: - Streaming wire format

nonisolated private struct StreamingChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let tools: [APITool]?
    let toolChoice: String?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream
        case toolChoice = "tool_choice"
    }
}

nonisolated private struct StreamingChunk: Decodable {
    let choices: [StreamingChoice]

    struct StreamingChoice: Decodable {
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCallDelta: Decodable {
        let index: Int
        let id: String?
        let function: FunctionDelta?

        struct FunctionDelta: Decodable {
            let name: String?
            let arguments: String?
        }
    }
}

// MARK: - JSON utility

nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }
}

extension JSONValue {
    static func schemaObject(
        properties: [String: JSONValue],
        required: [String] = [],
        description: String? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            object["required"] = .array(required.map { .string($0) })
        }
        if let description {
            object["description"] = .string(description)
        }
        return .object(object)
    }

    static func stringProperty(_ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    static func intProperty(_ description: String) -> JSONValue {
        .object([
            "type": .string("integer"),
            "description": .string(description),
        ])
    }

    static func boolProperty(_ description: String) -> JSONValue {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }
}
