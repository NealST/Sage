//
//  memories.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/endpoint/memories.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Unary POST over `URLSession`. Auth is `AuthProvider` (Bearer implemented).
//

import CodexProtocol
import Foundation

public struct MemoriesClient: Sendable {
    private let session: EndpointSession

    public init(
        urlSession: URLSession = .shared,
        provider: Provider,
        auth: SharedAuthProvider
    ) {
        self.session = EndpointSession(urlSession: urlSession, provider: provider, auth: auth)
    }

    init(session: EndpointSession) {
        self.session = session
    }

    public func withTelemetry(_ request: (any RequestTelemetry)?) -> MemoriesClient {
        MemoriesClient(session: session.withRequestTelemetry(request))
    }

    public static func path() -> String { "memories/trace_summarize" }

    public func summarize(
        body: JSONValue,
        extraHeaders: [String: String] = [:]
    ) async throws -> [MemorySummarizeOutput] {
        let data = try encodeJSON(body)
        let resp = try await session.execute(
            method: "POST",
            path: Self.path(),
            extraHeaders: extraHeaders,
            body: data
        )
        do {
            let parsed = try JSONDecoder().decode(SummarizeResponse.self, from: resp.body)
            return parsed.output
        } catch {
            throw ApiError.stream(String(describing: error))
        }
    }

    public func summarizeInput(
        _ input: MemorySummarizeInput,
        extraHeaders: [String: String] = [:]
    ) async throws -> [MemorySummarizeOutput] {
        let body: Data
        do {
            body = try encodeJSON(input)
        } catch {
            throw ApiError.stream("failed to encode memory summarize input: \(error)")
        }
        let value = try JSONDecoder().decode(JSONValue.self, from: body)
        return try await summarize(body: value, extraHeaders: extraHeaders)
    }
}

private struct SummarizeResponse: Decodable {
    var output: [MemorySummarizeOutput]
}
