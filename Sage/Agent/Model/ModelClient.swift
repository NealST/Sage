//
//  ModelClient.swift
//  Sage
//

import Foundation

nonisolated struct ToolCallProposal: Sendable, Equatable {
    let id: String
    let name: String
    let argumentsJSON: String
}

nonisolated struct ModelTurn: Sendable {
    let content: String?
    let toolCalls: [ToolCallProposal]
    let usage: TokenUsage

    init(content: String?, toolCalls: [ToolCallProposal], usage: TokenUsage = TokenUsage()) {
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

// MARK: - Streaming types

/// A single incremental chunk from the SSE stream.
enum StreamDelta: Sendable {
    /// A text content fragment.
    case text(String)
    /// Provider reasoning / thinking tokens. Displayed, not part of the reply.
    case thinking(String)
    /// A tool call fragment (index identifies which call is being built).
    case toolCallDelta(index: Int, id: String?, name: String?, arguments: String?)
    /// Provider-reported token usage (often on the final SSE chunk).
    case usage(input: Int, output: Int)
    /// The stream has finished; includes the stop reason.
    case done
}

enum ModelClientError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpStatus(Int, String)
    case rateLimited(retryAfter: TimeInterval?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add an API key in Settings before asking Sage."

        case .invalidURL:
            return "Model base URL is invalid."

        case .httpStatus(let code, let body):
            return Self.actionableMessage(code: code, body: body)

        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited — retry available in \(Int(seconds.rounded(.up)))s."
            }
            return "Rate limited by the API. Wait a moment and try again."

        case .decoding(let detail):
            return "Could not parse model response: \(detail)"
        }
    }

    /// Whether this error is transient and safe to auto-retry.
    var isTransient: Bool {
        switch self {
        case .rateLimited: return true

        case .httpStatus(let code, _):
            // 5xx = server error, 408 = request timeout
            return code >= 500 || code == 408

        default:
            return false
        }
    }

    private static func actionableMessage(code: Int, body: String) -> String {
        switch code {
        case 401:
            return "Authentication failed (401). Check your API key in Settings."

        case 403:
            return "Access denied (403). Your API key may lack permissions for this model."

        case 404:
            return "Model endpoint not found (404). Verify the base URL in Settings."

        case 408:
            return "Request timed out (408). Check your network connection."

        case 429:
            return "Rate limited (429). Too many requests — wait a moment."

        case 500...599:
            let short = body.prefix(120)
            return "Server error (\(code)). The provider may be experiencing issues.\(short.isEmpty ? "" : " \(short)")"

        default:
            let short = body.prefix(200)
            return "Model API error (\(code))\(short.isEmpty ? "." : ": \(short)")"
        }
    }
}

// MARK: - Retry policy

/// Exponential backoff retry for transient API errors.
/// Respects `Retry-After` headers and emits status updates for UI countdown.
nonisolated struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    static let `default` = Self(maxAttempts: 3, baseDelay: 1.0, maxDelay: 30.0)

    /// Calculates the delay for a given attempt (0-indexed).
    /// If a `retryAfter` value is provided (from 429 header), uses that instead.
    /// Includes ±25% jitter to avoid thundering herd on concurrent retries.
    func delay(attempt: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        if let serverDelay = retryAfter {
            return min(serverDelay, maxDelay)
        }
        // Exponential backoff: base * 2^attempt, capped at maxDelay
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let capped = min(exponential, maxDelay)
        // Add ±25% jitter to prevent synchronized retries across clients
        let jitter = capped * Double.random(in: -0.25...0.25)
        return max(0.5, capped + jitter)
    }
}

/// Status updates emitted during retry waits so the UI can show progress.
enum RetryStatus: Sendable {
    /// About to retry after a transient failure.
    case retrying(attempt: Int, total: Int, afterDelay: TimeInterval)
    /// Countdown tick — seconds remaining before next attempt.
    case waiting(secondsRemaining: Int)
}

actor ModelClient {
    /// Called on the main actor when retry status changes (for UI countdown).
    var onRetryStatus: (@MainActor @Sendable (RetryStatus) -> Void)?

    func setRetryStatusHandler(_ handler: @escaping @MainActor @Sendable (RetryStatus) -> Void) {
        onRetryStatus = handler
    }

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
    /// Automatically retries on transient errors (5xx, 429, timeout) with exponential backoff.
    func streamComplete(
        events: [AgentEvent],
        tools: [ToolDefinition],
        settings: ModelSettingsSnapshot,
        retryPolicy: RetryPolicy = .default
    ) async throws -> AsyncThrowingStream<StreamDelta, Error> {
        let url = try chatCompletionsURL(settings: settings)
        let encodedBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: settings.model,
                messages: APIMessage.messages(from: events),
                tools: tools.isEmpty ? nil : tools.map(APITool.init),
                toolChoice: tools.isEmpty ? nil : "auto",
                stream: true,
                streamOptions: .init(includeUsage: true)
            )
        )

        return try await withHTTPRetry(policy: retryPolicy) { attempt in
            let request = makeChatRequest(url: url, apiKey: settings.apiKey, body: encodedBody, timeout: 120)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            try Task.checkCancellation()

            let http = try requireHTTPResponse(response)
            if (200..<300).contains(http.statusCode) {
                return .success(buildStream(from: bytes))
            }

            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let text = String(data: errorData, encoding: .utf8) ?? ""
            return .retryableHTTP(status: http.statusCode, body: text, response: http, attempt: attempt)
        }
    }

    func complete(
        events: [AgentEvent],
        tools: [ToolDefinition],
        settings: ModelSettingsSnapshot,
        toolChoice: String? = nil,
        temperature: Double? = nil,
        retryPolicy: RetryPolicy = .default
    ) async throws -> ModelTurn {
        let url = try chatCompletionsURL(settings: settings)
        let resolvedChoice: String?
        if let toolChoice {
            resolvedChoice = tools.isEmpty ? nil : toolChoice
        } else {
            resolvedChoice = tools.isEmpty ? nil : "auto"
        }
        let encodedBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: settings.model,
                messages: APIMessage.messages(from: events),
                tools: tools.isEmpty ? nil : tools.map(APITool.init),
                toolChoice: resolvedChoice,
                temperature: temperature
            )
        )

        return try await withHTTPRetry(policy: retryPolicy) { attempt in
            let request = makeChatRequest(url: url, apiKey: settings.apiKey, body: encodedBody, timeout: 90)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()

            let http = try requireHTTPResponse(response)
            if (200..<300).contains(http.statusCode) {
                do {
                    let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                    let choice = decoded.choices.first?.message
                    let toolCalls = (choice?.toolCalls ?? []).map { call in
                        ToolCallProposal(
                            id: call.id,
                            name: call.function.name,
                            argumentsJSON: call.function.arguments
                        )
                    }
                    let usage = TokenUsage(
                        input: decoded.usage?.promptTokens ?? 0,
                        output: decoded.usage?.completionTokens ?? 0
                    )
                    return .success(
                        ModelTurn(content: choice?.content, toolCalls: toolCalls, usage: usage)
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw ModelClientError.decoding(error.localizedDescription)
                }
            }

            let text = String(data: data, encoding: .utf8) ?? ""
            return .retryableHTTP(status: http.statusCode, body: text, response: http, attempt: attempt)
        }
    }
}
