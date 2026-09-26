//
//  models.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/endpoint/models.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Unary GET over `URLSession`. Auth is `AuthProvider` (Bearer implemented).
//  Response-body limit is enforced after download.
//

import CodexProtocol
import Foundation

public struct ModelsClient: Sendable {
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

    public func withTelemetry(_ request: (any RequestTelemetry)?) -> ModelsClient {
        ModelsClient(session: session.withRequestTelemetry(request))
    }

    public static func path() -> String { "models" }

    public static func requestURL(provider: Provider, clientVersion: String) -> String {
        let separator = provider.baseUrl.contains("?") ? "&" : "?"
        let base = provider.baseUrl.hasSuffix("/")
            ? String(provider.baseUrl.dropLast())
            : provider.baseUrl
        return "\(base)/models\(separator)client_version=\(clientVersion)"
    }

    /// Builds a full catalog URL, preserving provider routing parameters and client version.
    public static func catalogRequestURL(
        provider: Provider,
        catalogURL: String,
        clientVersion: String
    ) throws -> String {
        guard var components = URLComponents(string: catalogURL),
              components.scheme != nil,
              components.host != nil
        else {
            throw ApiError.invalidRequest(message: "model_catalog_url must be an absolute URL")
        }
        var items = components.queryItems ?? []
        if let params = provider.queryParams {
            items.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: $0.value) })
        }
        items.append(URLQueryItem(name: "client_version", value: clientVersion))
        components.queryItems = items
        guard let url = components.url else {
            throw ApiError.invalidRequest(message: "model_catalog_url must be an absolute URL")
        }
        return url.absoluteString
    }

    public func listModels(
        requestURL: String,
        extraHeaders: [String: String] = [:],
        responseBodyLimitBytes: Int? = nil
    ) async throws -> ([ModelInfo], String?) {
        let (body, headerEtag) = try await listModelsRaw(
            requestURL: requestURL,
            extraHeaders: extraHeaders,
            responseBodyLimitBytes: responseBodyLimitBytes
        )
        do {
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: body)
            return (decoded.models, headerEtag)
        } catch {
            throw ApiError.stream(
                "failed to decode models response: \(error) (body: \(body.count) bytes)"
            )
        }
    }

    public func listModelsRaw(
        requestURL: String,
        extraHeaders: [String: String] = [:],
        responseBodyLimitBytes: Int? = nil
    ) async throws -> (Data, String?) {
        let resp = try await session.execute(
            method: "GET",
            path: Self.path(),
            extraHeaders: extraHeaders,
            body: nil
        ) { request in
            if let url = URL(string: requestURL) {
                request.url = url
            }
        }
        if let limit = responseBodyLimitBytes, resp.body.count > limit {
            throw ApiError.transport(
                .responseTooLarge(limit: limit, actual: resp.body.count)
            )
        }
        let headerEtag = parseHeaderStr(resp.headers, "etag")
        return (resp.body, headerEtag)
    }
}
