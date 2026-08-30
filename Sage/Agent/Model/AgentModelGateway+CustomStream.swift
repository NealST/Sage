//
//  AgentModelGateway+CustomStream.swift
//  Sage
//

import Foundation

extension AgentModelGateway {
    func streamComplete(includeTools: Bool = true) async throws -> ModelTurn {
        let req = await prepareRequest(includeTools: includeTools)
        let stream = try await modelClient.streamComplete(
            events: req.events,
            tools: req.tools,
            settings: req.settings
        )
        state.retryState = nil
        let collected = try await collectStream(stream)
        streaming.flush(collected.content)
        streaming.flushThinking(collected.thinking)
        compact?.considerBackground(occupancy: req.occupancy, tools: req.tools)
        return ModelTurn(
            content: collected.recovered.content,
            toolCalls: collected.recovered.calls,
            usage: collected.usage
        )
    }

    /// Streaming completion for a custom system/user pair.
    func streamCustom(
        system: String,
        user: String,
        role: ModelRole,
        onText: (String) -> Void
    ) async throws -> String {
        let snapshot = settings.snapshot(for: role)
        let stream = try await modelClient.streamComplete(
            events: [
                AgentEvent(kind: .systemInstruction, content: system),
                AgentEvent(kind: .userInput, content: user),
            ],
            tools: [],
            settings: snapshot
        )
        state.retryState = nil
        var chunks: [String] = []
        var thinkingChunks: [String] = []
        var usage = TokenUsage()
        for try await delta in stream {
            try Task.checkCancellation()
            switch delta {
            case .text(let chunk):
                chunks.append(chunk)
                onText(chunk)

            case .thinking(let chunk):
                thinkingChunks.append(chunk)
                streaming.publishThinking(thinkingChunks.joined())

            case .usage(let input, let output):
                usage.input = input
                usage.output = output

            case .toolCallDelta, .done:
                break
            }
        }
        state.addTokenUsage(usage)
        if !thinkingChunks.isEmpty {
            streaming.flushThinking(thinkingChunks.joined())
        }
        return chunks.joined()
    }

    private struct CollectedStream {
        var content: String
        var thinking: String
        var recovered: (content: String?, calls: [ToolCallProposal])
        var usage: TokenUsage
    }

    private func collectStream(
        _ stream: AsyncThrowingStream<StreamDelta, Error>
    ) async throws -> CollectedStream {
        var contentChunks: [String] = []
        var thinkingChunks: [String] = []
        var toolCallBuilders: [Int: ToolCallBuilder] = [:]
        var usage = TokenUsage()
        for try await delta in stream {
            try Task.checkCancellation()
            applyExecuteDelta(
                delta,
                contentChunks: &contentChunks,
                thinkingChunks: &thinkingChunks,
                toolCallBuilders: &toolCallBuilders,
                usage: &usage
            )
        }
        state.addTokenUsage(usage)
        let contentBuffer = contentChunks.joined()
        let recovered = TextToolCallParser.recover(
            from: contentBuffer,
            existing: structuredCalls(from: toolCallBuilders)
        )
        return CollectedStream(
            content: recovered.content ?? "",
            thinking: thinkingChunks.joined(),
            recovered: (recovered.content, recovered.calls),
            usage: usage
        )
    }

    private func applyExecuteDelta(
        _ delta: StreamDelta,
        contentChunks: inout [String],
        thinkingChunks: inout [String],
        toolCallBuilders: inout [Int: ToolCallBuilder],
        usage: inout TokenUsage
    ) {
        switch delta {
        case .text(let chunk):
            contentChunks.append(chunk)
            streaming.publish(TextToolCallParser.visibleText(in: contentChunks.joined()))

        case .thinking(let chunk):
            thinkingChunks.append(chunk)
            streaming.publishThinking(thinkingChunks.joined())

        case .toolCallDelta(let index, let id, let name, let arguments):
            var builder = toolCallBuilders[index] ?? ToolCallBuilder()
            if let id { builder.id = id }
            if let name { builder.name = name }
            if let arguments { builder.arguments += arguments }
            toolCallBuilders[index] = builder

        case .usage(let input, let output):
            usage.input = input
            usage.output = output

        case .done:
            break
        }
    }

    private func structuredCalls(
        from builders: [Int: ToolCallBuilder]
    ) -> [ToolCallProposal] {
        builders.keys.sorted().compactMap { index -> ToolCallProposal? in
            guard let builder = builders[index],
                  let id = builder.id,
                  let name = builder.name
            else { return nil }
            return ToolCallProposal(id: id, name: name, argumentsJSON: builder.arguments)
        }
    }
}
