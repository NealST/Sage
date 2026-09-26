//
//  endpoint_images.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/endpoint/images.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SPM unique basename (`images.swift` is the DTO file). Unary POST over
//  `URLSession`. Auth is `AuthProvider` (Bearer implemented).
//

import Foundation

let X_CODEX_IMAGEGEN_REQUEST_ID_HEADER = "x-codex-imagegen-request-id"

public struct ImagesClient: Sendable {
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

    public func withTelemetry(_ request: (any RequestTelemetry)?) -> ImagesClient {
        ImagesClient(session: session.withRequestTelemetry(request))
    }

    public func generate(
        _ request: ImageGenerationRequest,
        extraHeaders: [String: String] = [:]
    ) async throws -> (ImageResponse, String?) {
        try await postImageRequest(
            path: "images/generations",
            request: request,
            extraHeaders: extraHeaders,
            operation: "image generation"
        )
    }

    public func edit(
        _ request: ImageEditRequest,
        extraHeaders: [String: String] = [:]
    ) async throws -> (ImageResponse, String?) {
        try await postImageRequest(
            path: "images/edits",
            request: request,
            extraHeaders: extraHeaders,
            operation: "image edit"
        )
    }

    private func postImageRequest<R: Encodable>(
        path: String,
        request: R,
        extraHeaders: [String: String],
        operation: String
    ) async throws -> (ImageResponse, String?) {
        let body: Data
        do {
            body = try encodeJSON(request)
        } catch {
            throw ImageRequestError(
                error: .stream("failed to encode \(operation) request: \(error)"),
                imagegenRequestId: nil
            )
        }
        let resp: HttpUnaryResponse
        do {
            resp = try await session.execute(
                method: "POST",
                path: path,
                extraHeaders: extraHeaders,
                body: body
            )
        } catch let error as ApiError {
            throw ImageRequestError.fromApiError(error)
        }
        let imagegenRequestId = imagegenRequestIdFromHeaders(resp.headers)
        do {
            let decoded = try JSONDecoder().decode(ImageResponse.self, from: resp.body)
            return (decoded, imagegenRequestId)
        } catch {
            throw ImageRequestError(
                error: .stream("failed to decode \(operation) response: \(error)"),
                imagegenRequestId: imagegenRequestId
            )
        }
    }
}

/// Image request failure with the nested ImageGen request ID, when available.
public struct ImageRequestError: Error, Equatable, Sendable {
    public var error: ApiError
    public var imagegenRequestId: String?

    public init(error: ApiError, imagegenRequestId: String? = nil) {
        self.error = error
        self.imagegenRequestId = imagegenRequestId
    }

    static func fromApiError(_ error: ApiError) -> ImageRequestError {
        let imagegenRequestId: String?
        if case .transport(.http(_, _, let headers, _, _)) = error {
            imagegenRequestId = headers.flatMap(imagegenRequestIdFromHeaders)
        } else {
            imagegenRequestId = nil
        }
        return ImageRequestError(error: error, imagegenRequestId: imagegenRequestId)
    }

    public func intoParts() -> (ApiError, String?) {
        (error, imagegenRequestId)
    }
}

func imagegenRequestIdFromHeaders(_ headers: [String: String]) -> String? {
    parseHeaderStr(headers, X_CODEX_IMAGEGEN_REQUEST_ID_HEADER)
        .flatMap { $0.isEmpty ? nil : $0 }
}
