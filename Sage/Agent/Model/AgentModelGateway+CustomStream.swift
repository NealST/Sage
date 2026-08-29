//
//  AgentModelGateway+CustomStream.swift
//  Sage
//

import Foundation

extension AgentModelGateway {
    /// Streaming completion for a custom system/user pair. Does not publish tokens.
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
        var usage = TokenUsage()
        for try await delta in stream {
            try Task.checkCancellation()
            switch delta {
            case .text(let chunk):
                chunks.append(chunk)
                onText(chunk)

            case .usage(let input, let output):
                usage.input = input
                usage.output = output

            case .toolCallDelta, .done:
                break
            }
        }
        state.addTokenUsage(usage)
        return chunks.joined()
    }
}
