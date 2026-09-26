//
//  session.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/endpoint/session.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `codex_client::HttpTransport` maps to `URLSession`. Retry uses
//  `ApiRetryConfig` plus local `runWithRequestTelemetry`. Signing-capable
//  `AuthProvider.applyAuth` mutates `URLRequest`.
//

import CodexProtocol
import CodexUtils
import Foundation

struct HttpUnaryResponse: Sendable {
    var status: UInt16
    var headers: [String: String]
    var body: Data
    var url: String?
}

extension HttpUnaryResponse: WithHTTPStatus {
    var httpStatusCode: UInt16 { status }
}

struct HttpStreamResponse: Sendable {
    var status: UInt16
    var headers: [String: String]
    var bytes: URLSession.AsyncBytes
    var url: String?
}

extension HttpStreamResponse: WithHTTPStatus {
    var httpStatusCode: UInt16 { status }
}

final class EndpointSession: @unchecked Sendable {
    let urlSession: URLSession
    let provider: Provider
    let auth: SharedAuthProvider
    var requestTelemetry: (any RequestTelemetry)?

    init(
        urlSession: URLSession = .shared,
        provider: Provider,
        auth: SharedAuthProvider
    ) {
        self.urlSession = urlSession
        self.provider = provider
        self.auth = auth
        self.requestTelemetry = nil
    }

    func withRequestTelemetry(_ request: (any RequestTelemetry)?) -> EndpointSession {
        requestTelemetry = request
        return self
    }

    func buildURL(path: String) throws -> URL {
        try Self.buildURL(baseUrl: provider.baseUrl, path: path, queryParams: provider.queryParams)
    }

    static func buildURL(
        baseUrl: String,
        path: String,
        queryParams: [String: String]?
    ) throws -> URL {
        let trimmedBase = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(string: trimmedBase + trimmedPath) else {
            throw ApiError.invalidRequest(message: "invalid URL: \(trimmedBase)\(trimmedPath)")
        }
        if let queryParams, !queryParams.isEmpty {
            var items = components.queryItems ?? []
            items.append(contentsOf: queryParams.map { URLQueryItem(name: $0.key, value: $0.value) })
            components.queryItems = items
        }
        guard let url = components.url else {
            throw ApiError.invalidRequest(message: "invalid URL: \(trimmedBase)\(trimmedPath)")
        }
        return url
    }

    func execute(
        method: String,
        path: String,
        extraHeaders: [String: String],
        body: Data?,
        configure: ((inout URLRequest) -> Void)? = nil
    ) async throws -> HttpUnaryResponse {
        let result: Result<HttpUnaryResponse, TransportError> = await runWithRequestTelemetry(
            retry: provider.retry,
            telemetry: requestTelemetry
        ) {
            do {
                var request = try await self.makeRequest(
                    method: method,
                    path: path,
                    extraHeaders: extraHeaders,
                    body: body
                )
                configure?(&request)
                request = try await self.auth.applyAuth(request)
                let (data, response) = try await self.urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return .failure(.network("non-HTTP response"))
                }
                let headers = lowercaseHeaderMap(http.allHeaderFields)
                let status = UInt16(http.statusCode)
                if status >= 400 {
                    return .failure(
                        .http(
                            status: status,
                            url: request.url?.absoluteString,
                            headers: headers,
                            body: String(data: data, encoding: .utf8),
                            retryAfter: retryAfterFromHeaders(headers)
                        )
                    )
                }
                return .success(
                    HttpUnaryResponse(
                        status: status,
                        headers: headers,
                        body: data,
                        url: request.url?.absoluteString
                    )
                )
            } catch let error as AuthError {
                return .failure(TransportError(error))
            } catch let error as TransportError {
                return .failure(error)
            } catch let error as URLError where error.code == .timedOut {
                return .failure(.timeout)
            } catch {
                return .failure(.network(String(describing: error)))
            }
        }
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw ApiError.transport(error)
        }
    }

    func streamEncodedJSON(
        method: String,
        path: String,
        extraHeaders: [String: String],
        body: Data?,
        configure: ((inout URLRequest) -> Void)? = nil
    ) async throws -> HttpStreamResponse {
        let result: Result<HttpStreamResponse, TransportError> = await runWithRequestTelemetry(
            retry: provider.retry,
            telemetry: requestTelemetry
        ) {
            do {
                var request = try await self.makeRequest(
                    method: method,
                    path: path,
                    extraHeaders: extraHeaders,
                    body: body
                )
                configure?(&request)
                request = try await self.auth.applyAuth(request)
                let (bytes, response) = try await self.urlSession.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return .failure(.network("non-HTTP response"))
                }
                let headers = lowercaseHeaderMap(http.allHeaderFields)
                let status = UInt16(http.statusCode)
                if status >= 400 {
                    var collected = Data()
                    for try await byte in bytes {
                        collected.append(byte)
                        if collected.count > 64 * 1024 { break }
                    }
                    return .failure(
                        .http(
                            status: status,
                            url: request.url?.absoluteString,
                            headers: headers,
                            body: String(data: collected, encoding: .utf8),
                            retryAfter: retryAfterFromHeaders(headers)
                        )
                    )
                }
                return .success(
                    HttpStreamResponse(
                        status: status,
                        headers: headers,
                        bytes: bytes,
                        url: request.url?.absoluteString
                    )
                )
            } catch let error as AuthError {
                return .failure(TransportError(error))
            } catch let error as TransportError {
                return .failure(error)
            } catch let error as URLError where error.code == .timedOut {
                return .failure(.timeout)
            } catch {
                return .failure(.network(String(describing: error)))
            }
        }
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw ApiError.transport(error)
        }
    }

    func executeJSON<Body: Encodable>(
        method: String,
        path: String,
        extraHeaders: [String: String],
        body: Body?
    ) async throws -> HttpUnaryResponse {
        let data: Data?
        if let body {
            data = try encodeJSON(body)
        } else {
            data = nil
        }
        return try await execute(
            method: method,
            path: path,
            extraHeaders: extraHeaders,
            body: data
        )
    }

    private func makeRequest(
        method: String,
        path: String,
        extraHeaders: [String: String],
        body: Data?
    ) async throws -> URLRequest {
        let url = try buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        var headers = mergeHeaders(provider.headers, extraHeaders)
        if body != nil {
            headers["content-type"] = headers["content-type"] ?? "application/json"
        }
        applyHeaders(&request, headers)
        request.httpBody = body
        return request
    }
}

func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
    do {
        let text = try toAsciiJsonString(value)
        return Data(text.utf8)
    } catch {
        throw ApiError.stream("failed to encode request: \(error)")
    }
}

func decodeJSONData<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    try JSONDecoder().decode(type, from: data)
}

func retryAfterFromHeaders(_ headers: [String: String]) -> RetryAfter? {
    guard let raw = parseHeaderStr(headers, "retry-after") else { return nil }
    if let seconds = Double(raw) {
        return RetryAfter.fromDelay(.seconds(seconds))
    }
    return nil
}
