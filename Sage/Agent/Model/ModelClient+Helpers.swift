//
//  ModelClient+Helpers.swift
//  Sage
//

import Foundation

extension ModelClient {
    // MARK: - Private helpers

    enum RetryStep<Value> {
        case success(Value)
        case retryableHTTP(status: Int, body: String, response: HTTPURLResponse, attempt: Int)
    }

    func withHTTPRetry<Value>(
        policy: RetryPolicy,
        operation: (_ attempt: Int) async throws -> RetryStep<Value>
    ) async throws -> Value {
        var lastError: Error?
        for attempt in 0..<policy.maxAttempts {
            try Task.checkCancellation()
            do {
                switch try await operation(attempt) {
                case .success(let value):
                    return value

                case .retryableHTTP(let status, let body, let response, let attempt):
                    if let value: Value = try await handleRetryableHTTP(
                        RetryableHTTP(
                            status: status,
                            body: body,
                            response: response,
                            attempt: attempt,
                            policy: policy
                        ),
                        lastError: &lastError
                    ) {
                        return value
                    }
                    continue
                }
            } catch let error as ModelClientError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt < policy.maxAttempts - 1 {
                    try await performRetryWait(
                        attempt: attempt,
                        retryPolicy: policy,
                        retryAfter: nil
                    )
                    lastError = error
                    continue
                }
                throw error
            }
        }
        throw lastError ?? ModelClientError.httpStatus(-1, "Retry exhausted")
    }

    struct RetryableHTTP {
        var status: Int
        var body: String
        var response: HTTPURLResponse
        var attempt: Int
        var policy: RetryPolicy
    }

    func handleRetryableHTTP<Value>(
        _ http: RetryableHTTP,
        lastError: inout Error?
    ) async throws -> Value? {
        if http.status == 429 {
            let retryAfter = Self.parseRetryAfter(http.response)
            let error = ModelClientError.rateLimited(retryAfter: retryAfter)
            if http.attempt < http.policy.maxAttempts - 1 {
                try await performRetryWait(
                    attempt: http.attempt,
                    retryPolicy: http.policy,
                    retryAfter: retryAfter
                )
                lastError = error
                return nil
            }
            throw error
        }
        let error = ModelClientError.httpStatus(http.status, http.body)
        if error.isTransient, http.attempt < http.policy.maxAttempts - 1 {
            try await performRetryWait(
                attempt: http.attempt,
                retryPolicy: http.policy,
                retryAfter: nil
            )
            lastError = error
            return nil
        }
        throw error
    }

    func chatCompletionsURL(settings: ModelSettingsSnapshot) throws -> URL {
        guard !settings.apiKey.isEmpty else { throw ModelClientError.notConfigured }
        let trimmedBase = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/chat/completions") else {
            throw ModelClientError.invalidURL
        }
        return url
    }

    func makeChatRequest(
        url: URL,
        apiKey: String,
        body: Data,
        timeout: TimeInterval
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        request.httpBody = body
        return request
    }

    func requireHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw ModelClientError.httpStatus(-1, "No HTTP response")
        }
        return http
    }

    /// Builds the SSE parsing stream from a URLSession byte stream.
    func buildStream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let parseTask = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
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
                        yieldStreamChunk(chunk, continuation: continuation)
                    }
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

    func yieldStreamChunk(
        _ chunk: StreamingChunk,
        continuation: AsyncThrowingStream<StreamDelta, Error>.Continuation
    ) {
        if let usage = chunk.usage {
            continuation.yield(.usage(
                input: usage.promptTokens ?? 0,
                output: usage.completionTokens ?? 0
            ))
        }
        guard let delta = chunk.choices.first?.delta else { return }
        if let content = delta.content, !content.isEmpty {
            continuation.yield(.text(content))
        }
        if let toolCalls = delta.toolCalls {
            for toolCall in toolCalls {
                continuation.yield(.toolCallDelta(
                    index: toolCall.index,
                    id: toolCall.id,
                    name: toolCall.function?.name,
                    arguments: toolCall.function?.arguments
                ))
            }
        }
    }

    /// Waits with exponential backoff, emitting countdown ticks for UI feedback.
    func performRetryWait(
        attempt: Int,
        retryPolicy: RetryPolicy,
        retryAfter: TimeInterval?
    ) async throws {
        let delay = retryPolicy.delay(attempt: attempt, retryAfter: retryAfter)
        let totalSeconds = Int(delay.rounded(.up))

        let callback = onRetryStatus
        await callback?(.retrying(attempt: attempt + 1, total: retryPolicy.maxAttempts, afterDelay: delay))

        // Emit countdown ticks each second for UI
        for remaining in stride(from: totalSeconds, through: 1, by: -1) {
            try Task.checkCancellation()
            await callback?(.waiting(secondsRemaining: remaining))
            try await Task.sleep(for: .seconds(1))
        }

        // Signal wait complete — clears the countdown UI before the next attempt starts.
        await callback?(.waiting(secondsRemaining: 0))
    }

    /// Parses the `Retry-After` header (seconds or HTTP-date).
    static func parseRetryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        // Try as integer seconds first
        if let seconds = Double(value) {
            return seconds
        }
        // Try as HTTP-date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}

nonisolated struct ModelSettingsSnapshot: Sendable {
    let baseURL: String
    let model: String
    let apiKey: String
}
