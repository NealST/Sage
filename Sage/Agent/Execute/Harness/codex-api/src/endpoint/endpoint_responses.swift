//
//  endpoint_responses.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/endpoint/responses.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SPM unique basename (`sse/responses.swift` is the parser). `HttpTransport`
//  maps to `URLSession`. `Zstd` compression is a no-op. Auth is
//  `AuthProvider` (Bearer implemented; ChatGPT/OAuth deferred).
//

import CodexProtocol
import Foundation

public struct ResponsesClient: Sendable {
    private let session: EndpointSession
    private let sseTelemetry: (any SseTelemetry)?

    public init(
        urlSession: URLSession = .shared,
        provider: Provider,
        auth: SharedAuthProvider
    ) {
        self.session = EndpointSession(urlSession: urlSession, provider: provider, auth: auth)
        self.sseTelemetry = nil
    }

    init(session: EndpointSession, sseTelemetry: (any SseTelemetry)?) {
        self.session = session
        self.sseTelemetry = sseTelemetry
    }

    public func withTelemetry(
        request: (any RequestTelemetry)?,
        sse: (any SseTelemetry)?
    ) -> ResponsesClient {
        ResponsesClient(
            session: session.withRequestTelemetry(request),
            sseTelemetry: sse
        )
    }

    public func streamRequest(
        _ request: ResponsesApiRequest,
        options: ResponsesOptions = ResponsesOptions()
    ) async throws -> ResponseStream {
        let body: Data
        do {
            body = try encodeJSON(request)
        } catch {
            throw ApiError.stream("failed to encode responses request: \(error)")
        }
        var headers = options.extraHeaders
        if let threadId = options.threadId {
            insertHeader(&headers, "x-client-request-id", threadId)
        }
        headers = mergeHeaders(headers, buildSessionHeaders(
            sessionId: options.sessionId,
            threadId: options.threadId
        ))
        if let subagent = subagentHeader(options.sessionSource) {
            insertHeader(&headers, "x-openai-subagent", subagent)
        }
        return try await streamEncoded(
            body: body,
            extraHeaders: headers,
            compression: options.compression,
            turnState: options.turnState
        )
    }

    public func stream(
        body: JSONValue,
        extraHeaders: [String: String] = [:],
        compression: Compression = .none,
        turnState: TurnStateBox? = nil
    ) async throws -> ResponseStream {
        let data: Data
        do {
            data = try encodeJSON(body)
        } catch {
            throw ApiError.stream("failed to encode responses request: \(error)")
        }
        return try await streamEncoded(
            body: data,
            extraHeaders: extraHeaders,
            compression: compression,
            turnState: turnState
        )
    }

    private func streamEncoded(
        body: Data,
        extraHeaders: [String: String],
        compression: Compression,
        turnState: TurnStateBox?
    ) async throws -> ResponseStream {
        if case .zstd = compression {
            // Adapted: Zstd is a no-op (no compression crate).
        }
        let streamResponse = try await session.streamEncodedJSON(
            method: "POST",
            path: "/responses",
            extraHeaders: extraHeaders,
            body: body
        ) { request in
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        return spawnResponseStream(
            headers: streamResponse.headers,
            bytes: streamResponse.bytes,
            idleTimeout: session.provider.streamIdleTimeout,
            telemetry: sseTelemetry,
            turnState: turnState
        )
    }
}

public struct ResponsesOptions: Sendable {
    public var sessionId: String?
    public var threadId: String?
    public var sessionSource: SessionSource?
    public var extraHeaders: [String: String]
    public var compression: Compression
    public var turnState: TurnStateBox?

    public init(
        sessionId: String? = nil,
        threadId: String? = nil,
        sessionSource: SessionSource? = nil,
        extraHeaders: [String: String] = [:],
        compression: Compression = .none,
        turnState: TurnStateBox? = nil
    ) {
        self.sessionId = sessionId
        self.threadId = threadId
        self.sessionSource = sessionSource
        self.extraHeaders = extraHeaders
        self.compression = compression
        self.turnState = turnState
    }
}
