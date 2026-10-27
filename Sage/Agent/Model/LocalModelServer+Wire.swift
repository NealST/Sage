//
//  LocalModelServer+Wire.swift
//  Sage
//
//  OpenAI-compatible wire DTOs for the in-process local model server.
//  Mirrors ModelClientWire shapes; server-side needs Decodable requests
//  and Encodable responses, which the client-side types don't provide.
//

import Foundation

// MARK: - Request

nonisolated struct LocalServerRequestBody: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        enum Content {
            case text(String)
            case parts([Part])
        }

        struct Part: Decodable, Sendable {
            let type: String
            let text: String?
        }

        struct ToolCall: Decodable, Sendable {
            struct Function: Decodable, Sendable {
                let name: String
                let arguments: String?
            }

            let id: String?
            let function: Function
        }

        let role: String
        let content: Content?
        let toolCalls: [ToolCall]?
        let toolCallID: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(String.self, forKey: .role)
            toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
            if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
                content = .text(text)
            } else if let parts = try? container.decodeIfPresent([Part].self, forKey: .content) {
                content = .parts(parts ?? [])
            } else {
                content = nil
            }
        }
    }

    struct Tool: Decodable, Sendable {
        struct Function: Decodable, Sendable {
            let name: String
            let description: String?
            let parameters: AnyJSON?
        }

        let function: Function
    }

    let model: String
    let messages: [Message]
    let tools: [Tool]?
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature, stream
        case maxTokens = "max_tokens"
    }
}

/// Int-preserving JSON tree decoded into plain `Sendable` values for the
/// chat-template rendering context. Null members are dropped.
nonisolated struct AnyJSON: Decodable, Sendable {
    let value: any Sendable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dictionary = try? container.decode([String: AnyJSON?].self) {
            value = dictionary.compactMapValues { $0?.value }
        } else if let array = try? container.decode([AnyJSON?].self) {
            value = array.compactMap { $0?.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }
}

// MARK: - Non-streaming response

nonisolated struct CompletionEnvelope: Encodable, Sendable {
    struct Choice: Encodable, Sendable {
        struct Message: Encodable, Sendable {
            struct ToolCall: Encodable, Sendable {
                struct Function: Encodable, Sendable {
                    let name: String
                    let arguments: String
                }

                let id: String
                let type: String
                let function: Function

                init(id: String, function: Function) {
                    self.id = id
                    type = "function"
                    self.function = function
                }
            }

            let role: String
            let content: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }

            init(content: String?, toolCalls: [ToolCall]?) {
                role = "assistant"
                self.content = content
                self.toolCalls = toolCalls
            }
        }

        let index: Int
        let message: Message
        let finishReason: String

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }

        init(message: Message, finishReason: String) {
            index = 0
            self.message = message
            self.finishReason = finishReason
        }
    }

    struct Usage: Encodable, Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage

    init(model: String, choices: [Choice]) {
        id = "chatcmpl-local-\(UUID().uuidString.prefix(12))"
        object = "chat.completion"
        created = Int(Date().timeIntervalSince1970)
        self.model = model
        self.choices = choices
        usage = Usage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
    }
}

// MARK: - Streaming response

nonisolated struct ChunkEnvelope: Encodable, Sendable {
    struct Choice: Encodable, Sendable {
        let index: Int
        let delta: ChunkDelta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }

        init(delta: ChunkDelta, finishReason: String?) {
            index = 0
            self.delta = delta
            self.finishReason = finishReason
        }
    }

    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]

    init(id: String, created: Int, model: String, choices: [Choice]) {
        self.id = id
        object = "chat.completion.chunk"
        self.created = created
        self.model = model
        self.choices = choices
    }
}

nonisolated struct ChunkDelta: Encodable, Sendable {
    struct ToolCall: Encodable, Sendable {
        struct Function: Encodable, Sendable {
            let name: String
            let arguments: String
        }

        let index: Int
        let id: String?
        let type: String
        let function: Function

        init(index: Int, id: String?, function: Function) {
            self.index = index
            self.id = id
            type = "function"
            self.function = function
        }
    }

    let role: String?
    let content: String?
    let toolCalls: [ToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }

    init(content: String?, toolCalls: [ToolCall]?) {
        role = nil
        self.content = content
        self.toolCalls = toolCalls
    }
}

nonisolated typealias ChunkToolCall = ChunkDelta.ToolCall
