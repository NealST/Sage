//
//  files.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/files.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `RouteAwareClientPool` / streaming PUT map to `URLSession` unary
//  upload. `open_contents` is `() async throws -> Data` (reopened per
//  retry). ChatGPT account headers come from `AuthProvider`. OTEL events
//  are omitted. Backoff uses a local 125ms exponential.
//

import CodexProtocol
import Foundation

public let OPENAI_FILE_URI_PREFIX = "sediment://"
public let OPENAI_FILE_UPLOAD_LIMIT_BYTES: UInt64 = 512 * 1024 * 1024

private let openaiFileRequestTimeout: Duration = .seconds(60)
private let openaiFileBlobUploadTimeout: Duration = .seconds(5 * 60)
private let maxBlobUploadAttempts: UInt64 = 5
private let openaiFileFinalizeTimeout: Duration = .seconds(30)
private let openaiFileFinalizeRetryDelay: Duration = .milliseconds(250)
private let openaiFileUseCase = "codex"

public struct HostedFileUploadContext: Equatable, Sendable {
    public var connectorId: String
    public var actionName: String
    public var model: String

    public init(connectorId: String, actionName: String, model: String) {
        self.connectorId = connectorId
        self.actionName = actionName
        self.model = model
    }
}

public struct UploadedOpenAiFile: Equatable, Sendable {
    public var fileId: String
    public var uri: String
    public var downloadUrl: String
    public var fileName: String
    public var fileSizeBytes: UInt64
    public var mimeType: String?

    public init(
        fileId: String,
        uri: String,
        downloadUrl: String,
        fileName: String,
        fileSizeBytes: UInt64,
        mimeType: String?
    ) {
        self.fileId = fileId
        self.uri = uri
        self.downloadUrl = downloadUrl
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.mimeType = mimeType
    }
}

public enum OpenAiFileError: Error, Equatable, Sendable {
    case readContents(String)
    case fileTooLarge(fileName: String, sizeBytes: UInt64, limitBytes: UInt64)
    case request(url: String, source: String)
    case blobUploadRequest(
        host: String,
        elapsedMs: UInt64,
        errorKind: String,
        azureClientRequestId: String,
        source: String
    )
    case blobUploadStatus(
        host: String,
        status: UInt16,
        azureClientRequestId: String,
        azureRequestId: String,
        azureErrorCode: String
    )
    case unexpectedStatus(url: String, status: UInt16, body: String)
    case decode(url: String, source: String)
    case uploadNotReady(fileId: String)
    case uploadFailed(fileId: String, message: String)
}

extension OpenAiFileError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .readContents(let message):
            return "failed to open OpenAI file upload contents: \(message)"
        case .fileTooLarge(let fileName, let sizeBytes, let limitBytes):
            return "file `\(fileName)` is too large: \(sizeBytes) bytes exceeds the limit of \(limitBytes) bytes"
        case .request(let url, let source):
            return "failed to send OpenAI file request to \(url): \(source)"
        case .blobUploadRequest(let host, let elapsedMs, let errorKind, let azureClientRequestId, let source):
            return "OpenAI file blob upload to \(host) failed after \(elapsedMs) ms (\(errorKind), azure_client_request_id=\(azureClientRequestId)): \(source)"
        case .blobUploadStatus(let host, let status, let azureClientRequestId, let azureRequestId, let azureErrorCode):
            return "OpenAI file blob upload to \(host) failed with status \(status) (azure_client_request_id=\(azureClientRequestId), azure_request_id=\(azureRequestId), azure_error_code=\(azureErrorCode))"
        case .unexpectedStatus(let url, let status, let body):
            return "OpenAI file request to \(url) failed with status \(status): \(body)"
        case .decode(let url, let source):
            return "failed to parse OpenAI file response from \(url): \(source)"
        case .uploadNotReady(let fileId):
            return "OpenAI file upload for `\(fileId)` is not ready yet"
        case .uploadFailed(let fileId, let message):
            return "OpenAI file upload for `\(fileId)` failed: \(message)"
        }
    }
}

private struct CreateFileResponse: Decodable {
    var fileId: String
    var uploadUrl: String
    var pdfC2paReservation: Bool

    private enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case uploadUrl = "upload_url"
        case pdfC2paReservation = "pdf_c2pa_reservation"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileId = try container.decode(String.self, forKey: .fileId)
        uploadUrl = try container.decode(String.self, forKey: .uploadUrl)
        pdfC2paReservation = try container.decodeIfPresent(Bool.self, forKey: .pdfC2paReservation) ?? false
    }
}

private struct DownloadLinkResponse: Decodable {
    var status: String
    var downloadUrl: String?
    var fileName: String?
    var mimeType: String?
    var errorMessage: String?
    var fileSizeBytes: UInt64?

    private enum CodingKeys: String, CodingKey {
        case status
        case downloadUrl = "download_url"
        case fileName = "file_name"
        case mimeType = "mime_type"
        case errorMessage = "error_message"
        case fileSizeBytes = "file_size_bytes"
    }
}

public func openaiFileUri(_ fileId: String) -> String {
    "\(OPENAI_FILE_URI_PREFIX)\(fileId)"
}

/// Creates and finalizes one file record, reopening the same contents for blob PUT retries.
public func uploadOpenaiFile(
    baseUrl: String,
    auth: any AuthProvider,
    urlSession: URLSession = .shared,
    fileName: String,
    fileSizeBytes: UInt64,
    openContents: @escaping () async throws -> Data,
    hostedUpload: HostedFileUploadContext? = nil
) async throws -> UploadedOpenAiFile {
    if fileSizeBytes > OPENAI_FILE_UPLOAD_LIMIT_BYTES {
        throw OpenAiFileError.fileTooLarge(
            fileName: fileName,
            sizeBytes: fileSizeBytes,
            limitBytes: OPENAI_FILE_UPLOAD_LIMIT_BYTES
        )
    }

    let createURL = joinURL(baseUrl, "files")
    var createObject: [String: JSONValue] = [
        "file_name": .string(fileName),
        "file_size": .uint(fileSizeBytes),
        "use_case": .string(openaiFileUseCase),
    ]
    if let hostedUpload {
        createObject["codex_connector_id"] = .string(hostedUpload.connectorId)
        createObject["codex_action_name"] = .string(hostedUpload.actionName)
        createObject["codex_model"] = .string(hostedUpload.model)
    }
    let createRequest = JSONValue.object(createObject)

    let createBody: String
    do {
        createBody = try await authorizedJSON(
            urlSession: urlSession,
            auth: auth,
            method: "POST",
            url: createURL,
            json: createRequest
        )
    } catch let error as OpenAiFileError {
        throw error
    } catch {
        throw OpenAiFileError.request(url: createURL, source: String(describing: error))
    }

    let createPayload: CreateFileResponse
    do {
        createPayload = try JSONDecoder().decode(
            CreateFileResponse.self,
            from: Data(createBody.utf8)
        )
    } catch {
        throw OpenAiFileError.decode(url: createURL, source: String(describing: error))
    }

    let uploadHost = URL(string: createPayload.uploadUrl)?.host ?? "unknown-host"
    let uploadStartedAt = ContinuousClock.now
    let deadline = uploadStartedAt + openaiFileBlobUploadTimeout
    var retryDelay: Duration = .zero

    for attempt in 1...maxBlobUploadAttempts {
        let azureClientRequestId = UUID().uuidString.lowercased()
        func requestError(_ source: String, kind: String) -> OpenAiFileError {
            let elapsed = uploadStartedAt.duration(to: ContinuousClock.now)
            return .blobUploadRequest(
                host: uploadHost,
                elapsedMs: durationMillis(elapsed),
                errorKind: kind,
                azureClientRequestId: azureClientRequestId,
                source: source
            )
        }

        let remaining = ContinuousClock.now < deadline
            ? deadline - ContinuousClock.now
            : .zero
        if remaining == .zero {
            throw requestError("timeout", kind: "timeout")
        }

        let contents: Data
        do {
            contents = try await openContents()
        } catch {
            throw OpenAiFileError.readContents(String(describing: error))
        }

        var uploadRequest = URLRequest(url: URL(string: createPayload.uploadUrl)!)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.timeoutInterval = timeInterval(remaining)
        uploadRequest.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        uploadRequest.setValue(azureClientRequestId, forHTTPHeaderField: "x-ms-client-request-id")
        uploadRequest.setValue(String(fileSizeBytes), forHTTPHeaderField: "Content-Length")
        uploadRequest.httpBody = contents

        var status: UInt16?
        var cloudflareRayId = "missing"
        var azureRequestId = "missing"
        var azureErrorCode = "missing"
        var serverDelay: Duration?
        let error: OpenAiFileError
        let retryable: Bool

        do {
            let (data, response) = try await urlSession.data(for: uploadRequest)
            _ = data
            guard let http = response as? HTTPURLResponse else {
                throw requestError("non-HTTP response", kind: "other")
            }
            let headers = lowercaseHeaderMap(http.allHeaderFields)
            status = UInt16(http.statusCode)
            cloudflareRayId = parseHeaderStr(headers, "cf-ray") ?? "missing"
            azureRequestId = parseHeaderStr(headers, "x-ms-request-id") ?? "missing"
            azureErrorCode = parseHeaderStr(headers, "x-ms-error-code") ?? "missing"
            if (200..<300).contains(http.statusCode) {
                break
            }
            serverDelay = blobRetryAfter(headers)
            error = .blobUploadStatus(
                host: uploadHost,
                status: UInt16(http.statusCode),
                azureClientRequestId: azureClientRequestId,
                azureRequestId: azureRequestId,
                azureErrorCode: azureErrorCode
            )
            retryable = [502, 503, 504].contains(http.statusCode)
        } catch let fileError as OpenAiFileError {
            error = fileError
            if case .blobUploadRequest(_, _, let kind, _, _) = fileError {
                retryable = kind == "timeout" || kind == "connect" || kind == "body" || kind == "request"
            } else {
                retryable = false
            }
        } catch {
            let kind = blobTransportKind(error)
            let wrapped = requestError(String(describing: error), kind: kind)
            let willRetry = (kind == "timeout" || kind == "connect" || kind == "body" || kind == "request")
                && attempt < maxBlobUploadAttempts
                && fileBackoff(attempt) < remainingDuration(until: deadline)
            if !willRetry { throw wrapped }
            retryDelay = fileBackoff(attempt)
            try await Task.sleep(for: retryDelay)
            continue
        }

        _ = cloudflareRayId
        _ = status
        retryDelay = serverDelay ?? fileBackoff(attempt)
        let willRetry = retryable
            && attempt < maxBlobUploadAttempts
            && retryDelay < remainingDuration(until: deadline)
        if !willRetry {
            throw error
        }
        try await Task.sleep(for: retryDelay)
    }

    let finalizeURL = joinURL(baseUrl, "files/\(createPayload.fileId)/uploaded")
    var finalizeObject: [String: JSONValue] = [:]
    if createPayload.pdfC2paReservation {
        finalizeObject["pdf_c2pa_create_request"] = createRequest
    }
    let finalizeRequest = JSONValue.object(finalizeObject)
    let finalizeStartedAt = ContinuousClock.now

    while true {
        let finalizeBody: String
        do {
            finalizeBody = try await authorizedJSON(
                urlSession: urlSession,
                auth: auth,
                method: "POST",
                url: finalizeURL,
                json: finalizeRequest
            )
        } catch let error as OpenAiFileError {
            throw error
        } catch {
            throw OpenAiFileError.request(url: finalizeURL, source: String(describing: error))
        }

        let finalizePayload: DownloadLinkResponse
        do {
            finalizePayload = try JSONDecoder().decode(
                DownloadLinkResponse.self,
                from: Data(finalizeBody.utf8)
            )
        } catch {
            throw OpenAiFileError.decode(url: finalizeURL, source: String(describing: error))
        }

        switch finalizePayload.status {
        case "success":
            let size = finalizePayload.fileSizeBytes ?? fileSizeBytes
            guard let downloadUrl = finalizePayload.downloadUrl else {
                throw OpenAiFileError.uploadFailed(
                    fileId: createPayload.fileId,
                    message: "missing download_url"
                )
            }
            return UploadedOpenAiFile(
                fileId: createPayload.fileId,
                uri: openaiFileUri(createPayload.fileId),
                downloadUrl: downloadUrl,
                fileName: finalizePayload.fileName ?? fileName,
                fileSizeBytes: size,
                mimeType: finalizePayload.mimeType
            )
        case "retry":
            if finalizeStartedAt.duration(to: ContinuousClock.now) >= openaiFileFinalizeTimeout {
                throw OpenAiFileError.uploadNotReady(fileId: createPayload.fileId)
            }
            try await Task.sleep(for: openaiFileFinalizeRetryDelay)
        default:
            throw OpenAiFileError.uploadFailed(
                fileId: createPayload.fileId,
                message: finalizePayload.errorMessage ?? "upload finalization returned an error"
            )
        }
    }
}

private func authorizedJSON(
    urlSession: URLSession,
    auth: any AuthProvider,
    method: String,
    url: String,
    json: JSONValue
) async throws -> String {
    guard let parsed = URL(string: url) else {
        throw OpenAiFileError.request(url: url, source: "invalid URL")
    }
    var request = URLRequest(url: parsed)
    request.httpMethod = method
    request.timeoutInterval = timeInterval(openaiFileRequestTimeout)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var headers: [String: String] = [:]
    auth.addAuthHeaders(&headers)
    applyHeaders(&request, headers)
    request.httpBody = Data(json.encodedString().utf8)
    request = try await auth.applyAuth(request)

    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await urlSession.data(for: request)
    } catch {
        throw OpenAiFileError.request(url: url, source: String(describing: error))
    }
    guard let http = response as? HTTPURLResponse else {
        throw OpenAiFileError.request(url: url, source: "non-HTTP response")
    }
    let body = String(data: data, encoding: .utf8) ?? ""
    guard (200..<300).contains(http.statusCode) else {
        throw OpenAiFileError.unexpectedStatus(
            url: url,
            status: UInt16(http.statusCode),
            body: body
        )
    }
    return body
}

private func joinURL(_ baseUrl: String, _ path: String) -> String {
    let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
    let suffix = path.hasPrefix("/") ? path : "/\(path)"
    return trimmed + suffix
}

private func blobRetryAfter(_ headers: [String: String]) -> Duration? {
    if let delay = parseHeaderStr(headers, "x-ms-retry-after-ms").flatMap({ UInt64($0) }) {
        return .milliseconds(Int64(delay))
    }
    guard let value = parseHeaderStr(headers, "retry-after") else { return nil }
    if let seconds = UInt64(value) {
        return .seconds(Int64(seconds))
    }
    return nil
}

private func blobTransportKind(_ error: Error) -> String {
    guard let urlError = error as? URLError else { return "other" }
    switch urlError.code {
    case .timedOut:
        return "timeout"
    case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed:
        return "connect"
    default:
        return "request"
    }
}

private func fileBackoff(_ attempt: UInt64) -> Duration {
    let baseMs = 125.0
    let exp = pow(2.0, Double(max(Int64(attempt), 1) - 1))
    return .milliseconds(Int64(baseMs * exp))
}

private func remainingDuration(until deadline: ContinuousClock.Instant) -> Duration {
    let now = ContinuousClock.now
    if now >= deadline { return .zero }
    return deadline - now
}

private func durationMillis(_ duration: Duration) -> UInt64 {
    let (seconds, attoseconds) = duration.components
    let millis = seconds * 1000 + attoseconds / 1_000_000_000_000_000
    return UInt64(max(millis, 0))
}

private func timeInterval(_ duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
}
