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
    func complete(
        messages: [ChatMessage],
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
            messages: messages.map(APIMessage.init),
            tools: tools.isEmpty ? nil : tools.map(APITool.init),
            toolChoice: tools.isEmpty ? nil : "auto"
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
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
        } catch {
            throw ModelClientError.decoding(error.localizedDescription)
        }
    }
}

struct ModelSettingsSnapshot: Sendable {
    let baseURL: String
    let model: String
    let apiKey: String
}

// MARK: - Wire format

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIMessage]
    let tools: [APITool]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools
        case toolChoice = "tool_choice"
    }
}

private struct APIMessage: Encodable {
    let role: String
    let content: String?
    let toolCallID: String?
    let toolCalls: [APIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    init(_ message: ChatMessage) {
        role = message.role.rawValue
        // OpenAI wants content null (or omitted) when tool_calls are present sometimes;
        // empty string is widely accepted by compatible providers.
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            content = message.content.isEmpty ? nil : message.content
            self.toolCalls = toolCalls.map {
                APIToolCall(
                    id: $0.id,
                    type: "function",
                    function: APIToolCallFunction(name: $0.name, arguments: $0.argumentsJSON)
                )
            }
        } else {
            content = message.content
            self.toolCalls = nil
        }
        toolCallID = message.toolCallID
    }
}

private struct APIToolCall: Encodable {
    let id: String
    let type: String
    let function: APIToolCallFunction
}

private struct APIToolCallFunction: Encodable {
    let name: String
    let arguments: String
}

private struct APITool: Encodable {
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

private struct APIFunction: Encodable {
    let name: String
    let description: String
    let parameters: JSONValue
}

private struct ChatCompletionResponse: Decodable {
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

enum JSONValue: Codable, Sendable, Equatable {
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
}
