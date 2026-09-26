//
//  telemetry.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/telemetry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `eventsource_stream` / tungstenite poll types are replaced with local
//  `SsePollResult`. `run_with_retry` is a local URLSession retry loop.
//  `WebsocketTelemetry` is retained as a protocol only (no websocket impl).
//

import Foundation

/// Per-attempt HTTP request telemetry (stand-in for `codex_client::RequestTelemetry`).
public protocol RequestTelemetry: Sendable {
    func onRequest(
        attempt: UInt64,
        status: UInt16?,
        error: TransportError?,
        duration: Duration
    )
}

/// Outcome of one SSE idle-timeout poll.
public enum SsePollResult: Sendable {
    case event
    case transportError(String)
    case ended
    case idleTimeout
}

/// Generic SSE telemetry.
public protocol SseTelemetry: Sendable {
    func onSsePoll(_ result: SsePollResult, duration: Duration)
}

/// Telemetry for Responses WebSocket transport (protocol only; Phase 10).
public protocol WebsocketTelemetry: Sendable {
    func onWsRequest(duration: Duration, error: ApiError?, connectionReused: Bool)
    func onWsEvent(result: Result<String?, ApiError>, duration: Duration)
}

protocol WithHTTPStatus {
    var httpStatusCode: UInt16 { get }
}

func httpStatus(_ error: TransportError) -> UInt16? {
    if case .http(let status, _, _, _, _) = error {
        return status
    }
    return nil
}

func shouldRetry(
    _ error: TransportError,
    retry: RetryConfig,
    attempt: UInt64
) -> Bool {
    guard attempt < retry.maxAttempts else { return false }
    switch error {
    case .http(let status, _, _, _, _):
        if status == 429 { return retry.retry429 }
        if status >= 500 && status <= 599 { return retry.retry5xx }
        return false
    case .timeout, .network, .connection:
        return retry.retryTransport
    case .retryLimit, .policy, .build, .responseTooLarge:
        return false
    }
}

func retryDelay(retry: RetryConfig, attempt: UInt64) -> Duration {
    let (seconds, attoseconds) = retry.baseDelay.components
    let baseNanos = Double(seconds) * 1_000_000_000 + Double(attoseconds) / 1_000_000_000
    let factor = pow(2.0, Double(max(Int64(attempt), 1) - 1))
    return .nanoseconds(Int64(baseNanos * factor))
}

/// Wraps a request send with per-attempt telemetry and provider retry policy.
func runWithRequestTelemetry<T>(
    retry: RetryConfig,
    telemetry: (any RequestTelemetry)?,
    send: () async -> Result<T, TransportError>
) async -> Result<T, TransportError> {
    var attempt: UInt64 = 1
    var lastError: TransportError = .network("no request attempted")
    while attempt <= retry.maxAttempts {
        let start = ContinuousClock.now
        let result = await send()
        let elapsed = ContinuousClock.now - start
        switch result {
        case .success(let value):
            if let telemetry {
                let status = (value as? any WithHTTPStatus)?.httpStatusCode
                telemetry.onRequest(attempt: attempt, status: status, error: nil, duration: elapsed)
            }
            return .success(value)
        case .failure(let error):
            lastError = error
            if let telemetry {
                telemetry.onRequest(
                    attempt: attempt,
                    status: httpStatus(error),
                    error: error,
                    duration: elapsed
                )
            }
            if shouldRetry(error, retry: retry, attempt: attempt) {
                let delay = retryDelay(retry: retry, attempt: attempt)
                try? await Task.sleep(for: delay)
                attempt += 1
                continue
            }
            return .failure(error)
        }
    }
    return .failure(lastError)
}
