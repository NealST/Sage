//
//  responses_retry.swift
//  CodexCore
//
//  Port of codex-rs/core/src/responses_retry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session / TurnContext / otel retry macros wait on the Sage app
//  module. This file takes a ResponsesStreamRetrySink so CodexCore
//  stays Session-free. WebSocket fallback is a no-op while transport
//  is HTTP-only (Phase 10).
//

import CodexProtocol
import Foundation
import os

let initialConnectionRetryDelay: Duration = .seconds(5)
let maxConnectionRetryDelay: Duration = .seconds(60)

public enum ResponsesStreamRequest: Equatable, Sendable {
    case sampling
    case remoteCompactionV2
}

public struct ResponsesStreamRetryState: Sendable {
    public var retries: UInt64
    public var connectionRetries: UInt64
    public var connectionRetryDelay: Duration

    public init() {
        retries = 0
        connectionRetries = 0
        connectionRetryDelay = initialConnectionRetryDelay
    }
}

public struct ExhaustedResponseRetry: Sendable {
    public var turnId: String
    public var retryAt: ContinuousClock.Instant?

    public init(turnId: String, retryAt: ContinuousClock.Instant? = nil) {
        self.turnId = turnId
        self.retryAt = retryAt
    }
}

public protocol ResponsesStreamRetrySink: Sendable {
    var unboundedConnectionRetries: Bool { get }
    var sessionSourceIsInternal: Bool { get }
    var isAmazonBedrock: Bool { get }
    var responsesWebsocketEnabled: Bool { get }
    var turnId: String { get }

    func notifyStreamError(_ message: String, error: CodexErr) async
    func sendWarning(_ message: String) async
    func storeExhaustedRetry(_ retry: ExhaustedResponseRetry) async
}

public func handleResponseStreamError(
    retryState: inout ResponsesStreamRetryState,
    maxRetries: UInt64,
    err: CodexErr,
    trySwitchFallback: () -> Bool,
    sink: any ResponsesStreamRetrySink,
    request: ResponsesStreamRequest
) async throws {
    let retryCount = retryState.retries &+ 1
    guard let delay = err.retryDelay(retryCount: retryCount) else {
        throw err
    }
    let retryAfter = err.retryAfterValue()

    if sink.unboundedConnectionRetries
        && request == .sampling
        && isConnectionFailed(err)
        && !sink.sessionSourceIsInternal
        && !sink.isAmazonBedrock
    {
        let retryDelay = retryState.connectionRetryDelay
        Logger(subsystem: "sage.harness", category: "client").warning(
            "stream connection failed; waiting to retry turn=\(sink.turnId, privacy: .public)"
        )
        await sink.notifyStreamError("Reconnecting... waiting for network", error: err)
        retryState.connectionRetries &+= 1
        try await Task.sleep(for: retryDelay)
        retryState.connectionRetryDelay = min(retryDelay * 2, maxConnectionRetryDelay)
        return
    }

    if retryState.retries >= maxRetries && trySwitchFallback() {
        await sink.sendWarning("Falling back from WebSockets to HTTPS transport. \(err)")
        retryState.retries = 0
        return
    }

    if retryState.retries < maxRetries {
        retryState.retries = retryCount
        logRetry(request: request, turnId: sink.turnId, err: err, retries: retryCount, maxRetries: maxRetries, delay: delay)
        let reportError = retryCount > 1
            || _isDebugAssertConfiguration()
            || !sink.responsesWebsocketEnabled
        if reportError {
            await sink.notifyStreamError("Reconnecting... \(retryCount)/\(maxRetries)", error: err)
        }
        let sleepFor = retryAfter?.remainingDelay() ?? delay
        try await Task.sleep(for: sleepFor)
        return
    }

    await sink.storeExhaustedRetry(ExhaustedResponseRetry(turnId: sink.turnId))
    throw err
}

func isConnectionFailed(_ err: CodexErr) -> Bool {
    if case .connectionFailed = err.details { return true }
    return false
}

func logRetry(
    request: ResponsesStreamRequest,
    turnId: String,
    err: CodexErr,
    retries: UInt64,
    maxRetries: UInt64,
    delay: Duration
) {
    let logger = Logger(subsystem: "sage.harness", category: "client")
    switch request {
    case .sampling:
        logger.warning(
            "stream disconnected - retrying sampling request (\(retries)/\(maxRetries) in \(String(describing: delay), privacy: .public))... turn=\(turnId, privacy: .public) error=\(String(describing: err), privacy: .public)"
        )
    case .remoteCompactionV2:
        logger.warning(
            "remote compaction v2 stream failed; retrying request after delay turn=\(turnId, privacy: .public)"
        )
    }
}
