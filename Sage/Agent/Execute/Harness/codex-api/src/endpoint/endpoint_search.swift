//
//  endpoint_search.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/endpoint/search.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SPM unique basename (`search.swift` is the DTO file). Unary POST over
//  `URLSession`. Auth is `AuthProvider` (Bearer implemented).
//

import Foundation

/// The provider-relative endpoint for standalone web search.
let SEARCH_ENDPOINT = "alpha/search"

public struct SearchClient: Sendable {
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

    public func withTelemetry(_ request: (any RequestTelemetry)?) -> SearchClient {
        SearchClient(session: session.withRequestTelemetry(request))
    }

    public func search(
        _ request: SearchRequest,
        extraHeaders: [String: String] = [:]
    ) async throws -> SearchResponse {
        let body: Data
        do {
            body = try encodeJSON(request)
        } catch {
            throw ApiError.stream("failed to encode search request: \(error)")
        }
        let resp = try await session.execute(
            method: "POST",
            path: SEARCH_ENDPOINT,
            extraHeaders: extraHeaders,
            body: body
        )
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: resp.body)
        } catch {
            throw ApiError.stream("failed to decode search response: \(error)")
        }
    }
}
