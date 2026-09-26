//
//  api_bridge.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/api_bridge.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `http::StatusCode` maps to `UInt16`. `chrono::DateTime<Utc>` maps to
//  `Date`. `Box<RateLimitSnapshot>` is the snapshot value itself.
//  Base64 uses `Foundation`.
//

import CodexProtocol
import Foundation

public func mapApiError(_ err: ApiError) -> CodexErr {
    let retryAfter: RetryAfter?
    switch err {
    case .retryable(_, let value),
         .rateLimitExceeded(_, let value),
         .serverOverloaded(let value):
        retryAfter = value
    case .transport(.http(_, _, _, _, let value)):
        retryAfter = value
    case .transport, .api, .stream, .contextWindowExceeded, .quotaExceeded,
         .usageNotIncluded, .flexUnavailable, .rateLimit, .invalidRequest,
         .invalidPrompt, .cyberPolicy, .bioPolicy, .misalignmentPolicyViolation:
        retryAfter = nil
    }
    let error = mapApiErrorDetails(err)
    if let retryAfter {
        return error.withRetryAfter(retryAfter)
    }
    return error
}

private func mapApiErrorDetails(_ err: ApiError) -> CodexErr {
    switch err {
    case .contextWindowExceeded:
        return .contextWindowExceeded
    case .quotaExceeded:
        return .quotaExceeded
    case .usageNotIncluded:
        return .usageNotIncluded
    case .retryable(let message, _):
        return .stream(message)
    case .rateLimitExceeded(let message, _):
        return CodexErr.new(.rateLimitExceeded(message))
    case .stream(let msg):
        return .stream(msg)
    case .serverOverloaded:
        return .serverOverloaded
    case .flexUnavailable:
        return CodexErr.new(.flexUnavailable)
    case .api(let status, let message):
        let userMessage = apiErrorUserMessage(status: status, body: message)
        return .unexpectedStatus(
            UnexpectedResponseError(
                status: status,
                body: message,
                userMessage: userMessage,
                url: nil,
                cfRay: nil,
                requestId: nil,
                identityAuthorizationError: nil,
                identityErrorCode: nil
            )
        )
    case .invalidRequest(let message):
        return .invalidRequest(message)
    case .invalidPrompt(let message):
        return CodexErr.new(.invalidPrompt(message: message))
    case .cyberPolicy(let message):
        return CodexErr.new(.cyberPolicy(message: message))
    case .bioPolicy(let message):
        return CodexErr.new(.bioPolicy(message: message))
    case .misalignmentPolicyViolation(let message, let misalignment):
        return CodexErr.new(
            .misalignmentPolicyViolation(message: message, misalignment: misalignment)
        )
    case .transport(let transport):
        return mapTransportError(transport)
    case .rateLimit(let msg):
        return .stream(msg)
    }
}

private func mapTransportError(_ transport: TransportError) -> CodexErr {
    switch transport {
    case .http(let status, let url, let headers, let body, _):
        let bodyText = body ?? ""

        if status == 503,
           let value = try? JSONDecoder().decode(JSONValue.self, from: Data(bodyText.utf8)),
           let error = value.objectValue?["error"]
        {
            switch error.objectValue?["code"]?.stringValue {
            case "server_is_overloaded":
                return .serverOverloaded
            case "slow_down":
                let message = error.objectValue?["message"]?.stringValue ?? ""
                return CodexErr.new(.rateLimitExceeded(message))
            default:
                break
            }
        }

        if (status == 400 || status == 403),
           let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(bodyText.utf8)),
           let error = parsed.objectValue?["error"],
           error.objectValue?["code"]?.stringValue == misalignmentPolicyViolationErrorCode
        {
            let message = error.objectValue?["message"]?.stringValue
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ?? misalignmentPolicyViolationFallbackMessage
            let misalignment = error.objectValue?["misalignment"].flatMap { details -> MisalignmentErrorDetails? in
                guard let data = details.encodedString().data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(MisalignmentErrorDetails.self, from: data)
            }
            return CodexErr.new(
                .misalignmentPolicyViolation(message: message, misalignment: misalignment)
            )
        }

        if status == 400 {
            if let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(bodyText.utf8)),
               let error = parsed.objectValue?["error"],
               let code = error.objectValue?["code"]?.stringValue,
               code == cyberPolicyErrorCode
                || code == bioPolicyErrorCode
                || code == invalidPromptErrorCode
            {
                let fallbackMessage: String
                if code == bioPolicyErrorCode {
                    fallbackMessage = bioPolicyFallbackMessage
                } else if code == invalidPromptErrorCode {
                    fallbackMessage = invalidPromptFallbackMessage
                } else {
                    fallbackMessage = cyberPolicyFallbackMessage
                }
                let message = error.objectValue?["message"]?.stringValue
                    .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    ?? fallbackMessage
                if code == bioPolicyErrorCode {
                    return CodexErr.new(.bioPolicy(message: message))
                }
                if code == invalidPromptErrorCode {
                    return CodexErr.new(.invalidPrompt(message: message))
                }
                return CodexErr.new(.cyberPolicy(message: message))
            }
            if bodyText.contains("The image data you provided does not represent a valid image") {
                return .invalidImageRequest()
            }
            return .invalidRequest(bodyText)
        }
        if status == 500 {
            return .internalServerError
        }
        if status == 429 {
            if let bodyJson = try? JSONDecoder().decode(JSONValue.self, from: Data(bodyText.utf8)),
               let error = bodyJson.objectValue?["error"],
               let flex = parseFlexUnavailable(error)
            {
                return mapApiError(flex)
            }
            if let err = try? JSONDecoder().decode(UsageErrorResponse.self, from: Data(bodyText.utf8)) {
                if err.error.errorType == "usage_limit_reached" {
                    let limitId = extractHeader(headers, activeLimitHeader)
                    let promoMessage = headers.flatMap { parsePromoMessage($0) }
                    let rateLimitReachedType = headers.flatMap { parseRateLimitReachedType($0) }
                    var rateLimits = headers.flatMap { parseRateLimitForLimit($0, limitId: limitId) }
                    if var snapshot = rateLimits {
                        snapshot.rateLimitReachedType = rateLimitReachedType
                        rateLimits = snapshot
                    }
                    let resetsAt = err.error.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    return .usageLimitReached(
                        UsageLimitReachedError(
                            planType: err.error.planType,
                            resetsAt: resetsAt,
                            rateLimits: rateLimits,
                            promoMessage: promoMessage,
                            rateLimitReachedType: rateLimitReachedType
                        )
                    )
                }
                if err.error.errorType == "usage_not_included" {
                    return .usageNotIncluded
                }
                if err.error.errorType == "insufficient_quota"
                    || [
                        "insufficient_quota",
                        "credit_balance_exhausted",
                        "organization_spend_limit_exceeded",
                        "project_spend_limit_exceeded",
                        "organization_usage_limit_exceeded",
                    ].contains(err.error.code)
                {
                    return .quotaExceeded
                }
            }
            return .retryLimit(
                RetryLimitReachedError(
                    status: status,
                    requestId: extractRequestTrackingId(headers)
                )
            )
        }
        return .unexpectedStatus(
            UnexpectedResponseError(
                status: status,
                body: bodyText,
                userMessage: apiErrorUserMessage(status: status, body: bodyText),
                url: url,
                cfRay: extractHeader(headers, cfRayHeader),
                requestId: extractRequestId(headers),
                identityAuthorizationError: extractHeader(headers, xOpenaiAuthorizationErrorHeader),
                identityErrorCode: extractXErrorJsonCode(headers)
            )
        )
    case .retryLimit:
        return .retryLimit(
            RetryLimitReachedError(status: 500, requestId: nil)
        )
    case .timeout:
        return .requestTimeout
    case .policy(let denied):
        return .fatal(denied)
    case .connection(let source):
        return .connectionFailed(ConnectionFailedError(source: source))
    case .network(let msg), .build(let msg):
        return .stream(msg)
    case .responseTooLarge(let limit, let actual):
        return .invalidRequest(
            "response too large: \(actual) bytes exceeds limit of \(limit)"
        )
    }
}

private let activeLimitHeader = "x-codex-active-limit"
private let requestIdHeader = "x-request-id"
private let oaiRequestIdHeader = "x-oai-request-id"
private let cfRayHeader = "cf-ray"
private let xOpenaiAuthorizationErrorHeader = "x-openai-authorization-error"
private let xErrorJsonHeader = "x-error-json"
private let invalidPromptErrorCode = "invalid_prompt"
private let invalidPromptFallbackMessage = "Invalid request."
private let cyberPolicyErrorCode = "cyber_policy"
private let cyberPolicyFallbackMessage =
    "This request has been flagged for possible cybersecurity risk."
private let bioPolicyErrorCode = "bio_policy"
private let bioPolicyFallbackMessage = "This content was flagged for possible biological risk."
private let misalignmentPolicyViolationErrorCode = "misalignment_policy_violation"
private let misalignmentPolicyViolationFallbackMessage =
    "This request was blocked due to a misalignment policy violation."
private let cloudflareBlockedMessage =
    "Access blocked by Cloudflare. This usually happens when connecting from a restricted region"

private func extractRequestTrackingId(_ headers: [String: String]?) -> String? {
    extractRequestId(headers) ?? extractHeader(headers, cfRayHeader)
}

private func apiErrorUserMessage(status: UInt16, body: String) -> String? {
    if status == 403, body.contains("Cloudflare"), body.contains("blocked") {
        return "\(cloudflareBlockedMessage) (status \(status))"
    }
    return nil
}

private func extractRequestId(_ headers: [String: String]?) -> String? {
    extractHeader(headers, requestIdHeader) ?? extractHeader(headers, oaiRequestIdHeader)
}

private func extractHeader(_ headers: [String: String]?, _ name: String) -> String? {
    guard let headers else { return nil }
    return parseHeaderStr(headers, name)
}

private func extractXErrorJsonCode(_ headers: [String: String]?) -> String? {
    guard let encoded = extractHeader(headers, xErrorJsonHeader),
          let decoded = Data(base64Encoded: encoded),
          let parsed = try? JSONDecoder().decode(JSONValue.self, from: decoded)
    else { return nil }
    return parsed.objectValue?["error"]?.objectValue?["code"]?.stringValue
}

private struct UsageErrorResponse: Decodable {
    var error: UsageErrorBody
}

private struct UsageErrorBody: Decodable {
    var code: String?
    var errorType: String?
    var planType: AuthPlanType?
    var resetsAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case code
        case errorType = "type"
        case planType = "plan_type"
        case resetsAt = "resets_at"
    }
}
