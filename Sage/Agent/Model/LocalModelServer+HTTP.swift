//
//  LocalModelServer+HTTP.swift
//  Sage
//
//  Hummingbird wiring for the in-process OpenAI-compatible server:
//  GET /v1/models and POST /v1/chat/completions (plain + SSE, tool_calls).
//

import Foundation
import Hummingbird

extension LocalModelServer {

    func runServer() async {
        await LocalModelEngine.shared.start()

        let router = Router()
        router.get("v1/models") { _, _ in
            try await Self.modelsResponse()
        }
        router.post("v1/chat/completions") { request, _ in
            try await Self.chatCompletionsResponse(request: request)
        }

        let app = Application(
            router: router,
            configuration: ApplicationConfiguration(address: .hostname(port: 0)),
            onServerRunning: { channel in
                guard let port = channel.localAddress?.port else { return }
                LocalModelServer.shared.setEndpoint(URL(string: "http://127.0.0.1:\(port)/v1"))
            }
        )
        do {
            try await app.run()
        } catch {
            LocalModelServer.shared.setEndpoint(nil)
            LocalModelServer.shared.noteServerError(error.localizedDescription)
        }
    }

    // MARK: - Handlers

    private static func modelsResponse() async throws -> Response {
        let ids = await ModelCatalog.shared.installedLocalModelIDs
        struct Entry: Encodable {
            let id: String
            let object: String
            let created: Int
            let ownedBy: String

            enum CodingKeys: String, CodingKey {
                case id, object, created
                case ownedBy = "owned_by"
            }
        }
        struct ListResponse: Encodable {
            let object: String
            let data: [Entry]
        }
        let payload = ListResponse(
            object: "list",
            data: ids.map {
                Entry(id: $0, object: "model", created: 0, ownedBy: "sage-local")
            }
        )
        return try jsonOK(payload)
    }

    private static func chatCompletionsResponse(request: Request) async throws -> Response {
        let buffer = try await request.body.collect(upTo: 256 * 1024 * 1024)
        let data = Data(buffer.readableBytesView)
        let body: LocalServerRequestBody
        do {
            body = try JSONDecoder().decode(LocalServerRequestBody.self, from: data)
        } catch {
            return errorResponse(
                status: .badRequest,
                message: "Could not decode request body: \(error.localizedDescription)",
                code: "invalid_request"
            )
        }

        let installed = await ModelCatalog.shared.installedLocalModelIDs
        guard installed.contains(body.model) else {
            return errorResponse(
                status: .notFound,
                message: "Model '\(body.model)' is not downloaded. Add it in Settings → Models.",
                code: "model_not_found"
            )
        }
        guard LocalModelEngine.isAvailable else {
            return errorResponse(
                status: .serviceUnavailable,
                message: LocalModelEngineError.unsupportedArchitecture.localizedDescription,
                code: "ml_unavailable"
            )
        }

        let generationRequest = LocalGenerationRequest(
            modelID: body.model,
            messages: body.messages.map(message),
            tools: body.tools.map(toolSpecs),
            temperature: body.temperature,
            maxTokens: body.maxTokens
        )

        let stream: AsyncThrowingStream<LocalGenerationEvent, Error>
        do {
            stream = try await LocalModelEngine.shared.generate(generationRequest)
        } catch {
            return errorResponse(
                status: .serviceUnavailable,
                message: error.localizedDescription,
                code: "engine_error"
            )
        }

        if body.stream == true {
            return sseResponse(stream: stream, model: body.model)
        }

        var content = ""
        var toolCalls: [ToolCallProposal] = []
        var finishReason = "stop"
        do {
            for try await event in stream {
                switch event {
                case .text(let text):
                    content += text
                case .toolCall(let call):
                    toolCalls.append(call)
                case .finished(let reason):
                    if let reason { finishReason = reason }
                }
            }
        } catch {
            return errorResponse(
                status: .internalServerError,
                message: error.localizedDescription,
                code: "engine_error"
            )
        }
        if !toolCalls.isEmpty {
            finishReason = "tool_calls"
        }

        let payload = CompletionEnvelope(
            model: body.model,
            choices: [
                .init(
                    message: .init(
                        content: content.isEmpty ? nil : content,
                        toolCalls: toolCalls.map { call in
                            .init(
                                id: call.id,
                                function: .init(name: call.name, arguments: call.argumentsJSON)
                            )
                        }
                    ),
                    finishReason: finishReason
                ),
            ]
        )
        return try jsonOK(payload)
    }

    // MARK: - SSE

    private static func sseResponse(
        stream: AsyncThrowingStream<LocalGenerationEvent, Error>,
        model: String
    ) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody { writer in
                let encoder = JSONEncoder()
                let envelopeID = "chatcmpl-local-\(UUID().uuidString.prefix(12))"
                let created = Int(Date().timeIntervalSince1970)
                var toolCallIndex = 0

                func chunkBuffer(_ delta: ChunkDelta, finishReason: String?) throws -> ByteBuffer {
                    let envelope = ChunkEnvelope(
                        id: envelopeID,
                        created: created,
                        model: model,
                        choices: [.init(delta: delta, finishReason: finishReason)]
                    )
                    let json = try encoder.encode(envelope)
                    var buffer = ByteBuffer()
                    buffer.writeString("data: ")
                    buffer.writeBytes(json)
                    buffer.writeString("\n\n")
                    return buffer
                }

                do {
                    for try await event in stream {
                        switch event {
                        case .text(let text):
                            try await writer.write(
                                chunkBuffer(.init(content: text, toolCalls: nil), finishReason: nil)
                            )
                        case .toolCall(let call):
                            let deltaCall = ChunkToolCall(
                                index: toolCallIndex,
                                id: call.id,
                                function: .init(name: call.name, arguments: call.argumentsJSON)
                            )
                            toolCallIndex += 1
                            try await writer.write(
                                chunkBuffer(.init(content: nil, toolCalls: [deltaCall]), finishReason: nil)
                            )
                        case .finished(let reason):
                            let finish = reason == "tool_calls" ? "tool_calls" : "stop"
                            try await writer.write(
                                chunkBuffer(.init(content: nil, toolCalls: nil), finishReason: finish)
                            )
                        }
                    }
                    try await writer.write(ByteBuffer(string: "data: [DONE]\n\n"))
                } catch {
                    // Headers are already sent; dropping the connection is the
                    // only signal left. ModelClient surfaces this as
                    // streamTruncated rather than presenting a partial reply.
                    throw error
                }
                try await writer.finish(nil)
            }
        )
    }

    // MARK: - Mapping

    private static func message(from message: LocalServerRequestBody.Message) -> LocalChatMessage {
        LocalChatMessage(
            role: LocalChatMessage.Role(rawValue: message.role) ?? .user,
            content: textContent(message.content),
            toolCalls: message.toolCalls?.map { call in
                LocalChatMessage.ToolCall(
                    id: call.id,
                    name: call.function.name,
                    argumentsJSON: call.function.arguments ?? "{}"
                )
            },
            toolCallID: message.toolCallID
        )
    }

    private static func textContent(_ content: LocalServerRequestBody.Content?) -> String? {
        switch content {
        case .text(let text):
            return text.nilIfEmpty
        case .parts(let parts):
            return parts.compactMap(\.text).joined(separator: "\n\n").nilIfEmpty
        case nil:
            return nil
        }
    }

    private static func toolSpecs(from tools: [LocalServerRequestBody.Tool]) -> [[String: any Sendable]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.function.name,
                    "description": tool.function.description ?? "",
                    "parameters": (tool.function.parameters?.value as? [String: any Sendable]) ?? [:],
                ] as [String: any Sendable],
            ] as [String: any Sendable]
        }
    }

    // MARK: - Responses

    private static func jsonOK(_ payload: some Encodable) throws -> Response {
        let data = try JSONEncoder().encode(payload)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(bytes: data))
        )
    }

    private static func errorResponse(
        status: HTTPResponse.Status,
        message: String,
        code: String
    ) -> Response {
        struct APIError: Encodable {
            struct Inner: Encodable {
                let message: String
                let type: String
                let code: String
            }
            let error: Inner
        }
        let payload = APIError(error: .init(message: message, type: "invalid_request_error", code: code))
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}
