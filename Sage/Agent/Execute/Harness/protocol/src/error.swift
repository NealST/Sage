//
//  error.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/error.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  HTTP / retry / cancel types from `codex-http-client`, `http`, and
//  `codex-async-utils` are placeholders. Linux-only Landlock/seccomp variants
//  are omitted. Display strings match upstream.
//

import CodexUtils
import Foundation

public typealias CodexResult<T> = Result<T, CodexErr>

let errorMessageUiMaxBytes = 2 * 1024
let unexpectedResponseBodyMaxBytes = 1000

/// Placeholder for `codex_http_client::RetryAfter`.
public struct RetryAfter: Equatable, Sendable {
    public var remaining: Duration

    public init(remaining: Duration) {
        self.remaining = remaining
    }

    public func remainingDelay() -> Duration { remaining }

    public static func fromDelay(_ delay: Duration) -> RetryAfter? {
        RetryAfter(remaining: delay)
    }
}

/// Placeholder for `codex_http_client::HttpError`.
public struct HttpError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public var status: UInt16?
    public var url: String?

    public init(message: String, status: UInt16? = nil, url: String? = nil) {
        self.message = message; self.status = status; self.url = url
    }

    public var description: String { message }
}

public enum SandboxErr: Error, Equatable, Sendable, CustomStringConvertible {
    case denied(output: ExecToolCallOutput, networkPolicyDecision: NetworkPolicyDecisionPayload?)
    case timeout(output: ExecToolCallOutput)
    case signal(Int32)
    case landlockRestrict

    public var description: String {
        switch self {
        case .denied(let output, _):
            return "sandbox denied exec error, exit code: \(output.exitCode), stdout: \(output.stdout.text), stderr: \(output.stderr.text)"
        case .timeout:
            return "command timed out"
        case .signal:
            return "command was killed by a signal"
        case .landlockRestrict:
            return "Landlock was not able to fully enforce all sandbox rules"
        }
    }
}

public struct CodexErr: Error, Equatable, Sendable {
    public var details: CodexErrorDetails
    public var retryAfter: RetryAfter?

    public init(details: CodexErrorDetails, retryAfter: RetryAfter? = nil) {
        self.details = details
        self.retryAfter = retryAfter
    }

    public static func new(_ details: CodexErrorDetails) -> CodexErr {
        CodexErr(details: details)
    }

    public func detailsValue() -> CodexErrorDetails { details }

    public func withRetryAfter(_ retryAfter: RetryAfter) -> CodexErr {
        var copy = self
        copy.retryAfter = retryAfter
        return copy
    }

    public func retryAfterValue() -> RetryAfter? { retryAfter }

    public func serverRetryDelay() -> Duration? {
        retryAfter.map { $0.remainingDelay() }
    }

    public func retryDelay(retryCount: UInt64) -> Duration? {
        switch details {
        case .turnAborted, .sessionBudgetExceeded, .interrupted, .envVar, .fatal,
             .usageNotIncluded, .quotaExceeded, .invalidImageRequest, .invalidRequest,
             .invalidPrompt, .toolCollision, .refreshTokenFailed, .unsupportedOperation,
             .sandbox, .landlockSandboxExecutableNotProvided, .retryLimit,
             .contextWindowExceeded, .threadNotFound, .agentLimitReached, .spawn,
             .sessionConfiguredNotFirstEvent, .usageLimitReached, .serverOverloaded,
             .flexUnavailable, .cyberPolicy, .bioPolicy, .misalignmentPolicyViolation:
            return nil
        case .stream, .rateLimitExceeded, .timeout, .requestTimeout, .unexpectedStatus,
             .responseStreamFailed, .connectionFailed, .internalServerError,
             .internalAgentDied, .io, .json, .taskJoin:
            return serverRetryDelay() ?? localBackoff(retryCount)
        }
    }

    public func toCodexProtocolError() -> CodexErrorInfo {
        switch details {
        case .contextWindowExceeded: return .contextWindowExceeded
        case .sessionBudgetExceeded: return .sessionBudgetExceeded
        case .rateLimitExceeded: return .rateLimitExceeded
        case .usageLimitReached, .quotaExceeded, .usageNotIncluded: return .usageLimitExceeded
        case .serverOverloaded: return .serverOverloaded
        case .flexUnavailable: return .flexUnavailable
        case .cyberPolicy: return .cyberPolicy
        case .bioPolicy: return .bioPolicy
        case .invalidPrompt: return .invalidPrompt
        case .misalignmentPolicyViolation: return .misalignmentPolicyViolation
        case .retryLimit:
            return .responseTooManyFailedAttempts(httpStatusCode: httpStatusCodeValue())
        case .connectionFailed, .unexpectedStatus:
            return .httpConnectionFailed(httpStatusCode: httpStatusCodeValue())
        case .responseStreamFailed:
            return .responseStreamConnectionFailed(httpStatusCode: httpStatusCodeValue())
        case .refreshTokenFailed: return .unauthorized
        case .sessionConfiguredNotFirstEvent, .internalServerError, .internalAgentDied:
            return .internalServerError
        case .unsupportedOperation, .threadNotFound, .agentLimitReached:
            return .badRequest
        case .sandbox: return .sandboxError
        default: return .other
        }
    }

    public func toErrorEvent(messagePrefix: String? = nil) -> ErrorEvent {
        let errorMessage = description
        let message = messagePrefix.map { "\($0): \(errorMessage)" } ?? errorMessage
        let misalignment: MisalignmentErrorDetails?
        if case .misalignmentPolicyViolation(_, let details) = details {
            misalignment = details
        } else {
            misalignment = nil
        }
        return ErrorEvent(
            message: message,
            errorInfo: toCodexProtocolError(),
            misalignment: misalignment)
    }

    public func httpStatusCodeValue() -> UInt16? {
        switch details {
        case .flexUnavailable: return 429
        case .retryLimit(let err): return err.status
        case .unexpectedStatus(let err): return err.status
        case .connectionFailed(let err): return err.source.status
        case .responseStreamFailed(let err): return err.source.status
        default: return nil
        }
    }

    public static let turnAborted = CodexErr(details: .turnAborted)
    public static let sessionBudgetExceeded = CodexErr(details: .sessionBudgetExceeded)
    public static let contextWindowExceeded = CodexErr(details: .contextWindowExceeded)
    public static let sessionConfiguredNotFirstEvent = CodexErr(details: .sessionConfiguredNotFirstEvent)
    public static let timeout = CodexErr(details: .timeout)
    public static let requestTimeout = CodexErr(details: .requestTimeout)
    public static let spawn = CodexErr(details: .spawn)
    public static let interrupted = CodexErr(details: .interrupted)
    public static let serverOverloaded = CodexErr(details: .serverOverloaded)
    public static let quotaExceeded = CodexErr(details: .quotaExceeded)
    public static let usageNotIncluded = CodexErr(details: .usageNotIncluded)
    public static let internalServerError = CodexErr(details: .internalServerError)
    public static let internalAgentDied = CodexErr(details: .internalAgentDied)
    public static let landlockSandboxExecutableNotProvided =
        CodexErr(details: .landlockSandboxExecutableNotProvided)

    public static func stream(_ message: String) -> CodexErr { CodexErr(details: .stream(message)) }
    public static func threadNotFound(_ threadId: ThreadId) -> CodexErr {
        CodexErr(details: .threadNotFound(threadId))
    }
    public static func unexpectedStatus(_ error: UnexpectedResponseError) -> CodexErr {
        CodexErr(details: .unexpectedStatus(error))
    }
    public static func invalidRequest(_ message: String) -> CodexErr {
        CodexErr(details: .invalidRequest(message))
    }
    public static func io(_ message: String) -> CodexErr {
        CodexErr(details: .io(message))
    }
    public static func usageLimitReached(_ error: UsageLimitReachedError) -> CodexErr {
        CodexErr(details: .usageLimitReached(error))
    }
    public static func responseStreamFailed(_ error: ResponseStreamFailed) -> CodexErr {
        CodexErr(details: .responseStreamFailed(error))
    }
    public static func connectionFailed(_ error: ConnectionFailedError) -> CodexErr {
        CodexErr(details: .connectionFailed(error))
    }
    public static func retryLimit(_ error: RetryLimitReachedError) -> CodexErr {
        CodexErr(details: .retryLimit(error))
    }
    public static func sandbox(_ error: SandboxErr) -> CodexErr {
        CodexErr(details: .sandbox(error))
    }
    public static func unsupportedOperation(_ message: String) -> CodexErr {
        CodexErr(details: .unsupportedOperation(message))
    }
    public static func refreshTokenFailed(_ error: RefreshTokenFailedError) -> CodexErr {
        CodexErr(details: .refreshTokenFailed(error))
    }
    public static func fatal(_ message: String) -> CodexErr {
        CodexErr(details: .fatal(message))
    }
    public static func envVar(_ error: EnvVarError) -> CodexErr {
        CodexErr(details: .envVar(error))
    }
    public static func invalidImageRequest() -> CodexErr {
        CodexErr(details: .invalidImageRequest)
    }
}

public enum CodexErrorDetails: Equatable, Sendable {
    case turnAborted
    case sessionBudgetExceeded
    case stream(String)
    case rateLimitExceeded(String)
    case contextWindowExceeded
    case threadNotFound(ThreadId)
    case agentLimitReached(maxThreads: Int)
    case sessionConfiguredNotFirstEvent
    case timeout
    case requestTimeout
    case spawn
    case interrupted
    case unexpectedStatus(UnexpectedResponseError)
    case invalidRequest(String)
    case invalidPrompt(message: String)
    case toolCollision(String)
    case invalidImageRequest
    case usageLimitReached(UsageLimitReachedError)
    case serverOverloaded
    case flexUnavailable
    case cyberPolicy(message: String)
    case bioPolicy(message: String)
    case misalignmentPolicyViolation(message: String, misalignment: MisalignmentErrorDetails?)
    case responseStreamFailed(ResponseStreamFailed)
    case connectionFailed(ConnectionFailedError)
    case quotaExceeded
    case usageNotIncluded
    case internalServerError
    case retryLimit(RetryLimitReachedError)
    case internalAgentDied
    case sandbox(SandboxErr)
    case landlockSandboxExecutableNotProvided
    case unsupportedOperation(String)
    case refreshTokenFailed(RefreshTokenFailedError)
    case fatal(String)
    case io(String)
    case json(String)
    case taskJoin(String)
    case envVar(EnvVarError)
}

extension CodexErrorDetails: CustomStringConvertible {
    public var description: String {
        switch self {
        case .turnAborted:
            return "turn aborted. Something went wrong? Hit `/feedback` to report the issue."
        case .sessionBudgetExceeded:
            return "shared rollout token budget exhausted"
        case .stream(let message):
            return "stream disconnected before completion: \(message)"
        case .rateLimitExceeded(let message):
            return "rate limit exceeded: \(message)"
        case .contextWindowExceeded:
            return "Codex ran out of room in the model's context window. Start a new thread or clear earlier history before retrying."
        case .threadNotFound(let threadId):
            return "no thread with id: \(threadId)"
        case .agentLimitReached:
            return "agent thread limit reached"
        case .sessionConfiguredNotFirstEvent:
            return "session configured event was not the first event in the stream"
        case .timeout:
            return "timeout waiting for child process to exit"
        case .requestTimeout:
            return "request timed out"
        case .spawn:
            return "spawn failed: child stdout/stderr not captured"
        case .interrupted:
            return "interrupted (Ctrl-C). Something went wrong? Hit `/feedback` to report the issue."
        case .unexpectedStatus(let error):
            return error.description
        case .invalidRequest(let message):
            return message
        case .invalidPrompt(let message):
            return message
        case .toolCollision(let name):
            return "duplicate tool: \(name)"
        case .invalidImageRequest:
            return "Image poisoning"
        case .usageLimitReached(let error):
            return error.description
        case .serverOverloaded:
            return "Selected model is at capacity. Please try a different model."
        case .flexUnavailable:
            return "Flex capacity unavailable."
        case .cyberPolicy(let message), .bioPolicy(let message):
            return message
        case .misalignmentPolicyViolation(let message, _):
            return message
        case .responseStreamFailed(let error):
            return error.description
        case .connectionFailed(let error):
            return error.description
        case .quotaExceeded:
            return "Quota exceeded. Check your plan and billing details."
        case .usageNotIncluded:
            return "To use Codex with your ChatGPT plan, upgrade to Plus: https://chatgpt.com/explore/plus."
        case .internalServerError:
            return "We’re currently experiencing high demand, which may cause temporary errors."
        case .retryLimit(let error):
            return error.description
        case .internalAgentDied:
            return "internal error; agent loop died unexpectedly"
        case .sandbox(let error):
            return "sandbox error: \(error)"
        case .landlockSandboxExecutableNotProvided:
            return "codex-linux-sandbox was required but not provided"
        case .unsupportedOperation(let message):
            return "unsupported operation: \(message)"
        case .refreshTokenFailed(let error):
            return error.description
        case .fatal(let message):
            return "Fatal error: \(message)"
        case .io(let message), .json(let message), .taskJoin(let message):
            return message
        case .envVar(let error):
            return error.description
        }
    }
}

extension CodexErr: CustomStringConvertible {
    public var description: String { details.description }
}

extension CodexErr: CustomDebugStringConvertible {
    public var debugDescription: String {
        if case .stream(let message) = details {
            let delay = serverRetryDelay().map { "Some(\($0))" } ?? "None"
            return "Stream(\"\(message)\", \(delay))"
        }
        return String(describing: details)
    }
}

public struct ConnectionFailedError: Equatable, Sendable, CustomStringConvertible {
    public var source: HttpError
    public init(source: HttpError) { self.source = source }
    public var description: String { "Connection failed: \(source)" }
}

public struct ResponseStreamFailed: Equatable, Sendable, CustomStringConvertible {
    public var source: HttpError
    public var requestId: String?

    public init(source: HttpError, requestId: String? = nil) {
        self.source = source; self.requestId = requestId
    }

    public var description: String {
        let suffix = requestId.map { ", request id: \($0)" } ?? ""
        return "Error while reading the server response: \(source)\(suffix)"
    }
}

public struct UnexpectedResponseError: Equatable, Sendable, CustomStringConvertible {
    public var status: UInt16
    public var body: String
    public var userMessage: String?
    public var url: String?
    public var cfRay: String?
    public var requestId: String?
    public var identityAuthorizationError: String?
    public var identityErrorCode: String?

    public init(
        status: UInt16, body: String, userMessage: String? = nil, url: String? = nil,
        cfRay: String? = nil, requestId: String? = nil,
        identityAuthorizationError: String? = nil, identityErrorCode: String? = nil
    ) {
        self.status = status; self.body = body; self.userMessage = userMessage
        self.url = url; self.cfRay = cfRay; self.requestId = requestId
        self.identityAuthorizationError = identityAuthorizationError
        self.identityErrorCode = identityErrorCode
    }

    func displayBody() -> String {
        if let message = extractErrorMessage() { return message }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Unknown error" }
        return truncateWithEllipsis(trimmed, maxBytes: unexpectedResponseBodyMaxBytes)
    }

    func extractErrorMessage() -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let root) = json,
              case .object(let error)? = root["error"],
              case .string(let message)? = error["message"]
        else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var description: String {
        var message = userMessage ?? "unexpected status \(status): \(displayBody())"
        if let url { message += ", url: \(url)" }
        if let cfRay { message += ", cf-ray: \(cfRay)" }
        if let requestId { message += ", request id: \(requestId)" }
        if let identityAuthorizationError { message += ", auth error: \(identityAuthorizationError)" }
        if let identityErrorCode { message += ", auth error code: \(identityErrorCode)" }
        return message
    }
}

public struct RetryLimitReachedError: Equatable, Sendable, CustomStringConvertible {
    public var status: UInt16
    public var requestId: String?

    public init(status: UInt16, requestId: String? = nil) {
        self.status = status; self.requestId = requestId
    }

    public var description: String {
        let suffix = requestId.map { ", request id: \($0)" } ?? ""
        return "exceeded retry limit, last status: \(status)\(suffix)"
    }
}

public struct UsageLimitReachedError: Equatable, Sendable, CustomStringConvertible {
    public var planType: AuthPlanType?
    public var resetsAt: Date?
    public var rateLimits: RateLimitSnapshot?
    public var promoMessage: String?
    public var rateLimitReachedType: RateLimitReachedType?

    public init(
        planType: AuthPlanType? = nil,
        resetsAt: Date? = nil,
        rateLimits: RateLimitSnapshot? = nil,
        promoMessage: String? = nil,
        rateLimitReachedType: RateLimitReachedType? = nil
    ) {
        self.planType = planType
        self.resetsAt = resetsAt
        self.rateLimits = rateLimits
        self.promoMessage = promoMessage
        self.rateLimitReachedType = rateLimitReachedType
    }

    public var description: String {
        if let limitName = rateLimits?.limitName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !limitName.isEmpty,
           limitName.lowercased() != "codex",
           limitName.lowercased() != "gpt-reserve"
        {
            return "You’ve hit your usage limit for \(limitName). Switch to another model now,\(retrySuffixAfterOr(resetsAt))"
        }
        if let rateLimitReachedType {
            switch rateLimitReachedType {
            case .workspaceOwnerCreditsDepleted:
                return "Your workspace is out of credits. Add credits to continue."
            case .workspaceMemberCreditsDepleted:
                return "Your workspace is out of credits. Ask your workspace owner to refill in order to continue."
            case .workspaceOwnerUsageLimitReached:
                return "You hit your spend cap set in your workspace. Increase your spend cap to continue."
            case .workspaceMemberUsageLimitReached:
                return "You hit your spend cap set by the owner of your workspace. Ask an owner to increase your spend cap to continue."
            case .rateLimitReached:
                break
            }
        }
        if let promoMessage {
            return "You’ve hit your usage limit. \(promoMessage),\(retrySuffixAfterOr(resetsAt))"
        }
        switch planType {
        case .known(.plus):
            return "You’ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits\(retrySuffixAfterOr(resetsAt))"
        case .known(.team), .known(.selfServeBusinessProLite), .known(.selfServeBusinessUsageBased),
             .known(.business), .known(.ent26), .known(.enterpriseCbpAutomation),
             .known(.enterpriseCbpUsageBased):
            return "You’ve hit your usage limit. To get more access now, send a request to your admin\(retrySuffixAfterOr(resetsAt))"
        case .known(.free), .known(.go):
            return "You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus),\(retrySuffixAfterOr(resetsAt))"
        case .known(.pro), .known(.proLite), .known(.proMax):
            return "You’ve hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits\(retrySuffixAfterOr(resetsAt))"
        case .known(.enterprise), .known(.edu), .known(.eduPlus), .known(.eduPro):
            return "You’ve hit your usage limit.\(retrySuffix(resetsAt))"
        case .unknown, .none:
            return "You’ve hit your usage limit.\(retrySuffix(resetsAt))"
        }
    }
}

public struct EnvVarError: Equatable, Sendable, CustomStringConvertible {
    public var varName: String
    public var instructions: String?

    public init(varName: String, instructions: String? = nil) {
        self.varName = varName; self.instructions = instructions
    }

    public var description: String {
        var message = "Missing environment variable: `\(varName)`."
        if let instructions { message += " \(instructions)" }
        return message
    }
}

public func getErrorMessageUi(_ error: CodexErr) -> String {
    let message: String
    switch error.details {
    case .sandbox(.denied(let output, _)):
        let aggregated = output.aggregatedOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aggregated.isEmpty {
            message = output.aggregatedOutput.text
        } else {
            let stderr = output.stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = output.stdout.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (stderr.isEmpty, stdout.isEmpty) {
            case (false, false): message = "\(output.stderr.text)\n\(output.stdout.text)"
            case (false, true): message = output.stderr.text
            case (true, false): message = output.stdout.text
            case (true, true):
                message = "command failed inside sandbox with exit code \(output.exitCode)"
            }
        }
    case .sandbox(.timeout(let output)):
        let millis = durationMillis(output.duration)
        message = "error: command timed out after \(millis) ms"
    default:
        message = error.description
    }
    return truncateText(message, policy: .bytes(errorMessageUiMaxBytes))
}

func retrySuffix(_ resetsAt: Date?) -> String {
    if let resetsAt {
        return " Try again at \(formatRetryTimestamp(resetsAt))."
    }
    return " Try again later."
}

func retrySuffixAfterOr(_ resetsAt: Date?) -> String {
    if let resetsAt {
        return " or try again at \(formatRetryTimestamp(resetsAt))."
    }
    return " or try again later."
}

func formatRetryTimestamp(_ resetsAt: Date) -> String {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    if calendar.isDateInToday(resetsAt) {
        formatter.dateFormat = "h:mm a"
    } else {
        let day = calendar.component(.day, from: resetsAt)
        formatter.dateFormat = "MMM d'\(daySuffix(day))', yyyy h:mm a"
    }
    return formatter.string(from: resetsAt)
}

func daySuffix(_ day: Int) -> String {
    switch day {
    case 11, 12, 13: return "th"
    default:
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

func truncateWithEllipsis(_ text: String, maxBytes: Int) -> String {
    if text.utf8.count <= maxBytes { return text }
    var cut = maxBytes
    let utf8 = Array(text.utf8)
    while cut > 0 && cut < utf8.count && !isCharBoundary(utf8, cut) {
        cut -= 1
    }
    return String(decoding: utf8.prefix(cut), as: UTF8.self) + "..."
}

func isCharBoundary(_ utf8: [UInt8], _ index: Int) -> Bool {
    if index == 0 || index == utf8.count { return true }
    return utf8[index] & 0xC0 != 0x80
}

func truncateText(_ content: String, policy: TruncationPolicy) -> String {
    switch policy {
    case .bytes(let bytes):
        return truncateMiddleChars(content, maxBytes: bytes)
    case .tokens(let tokens):
        return truncateMiddleWithTokenBudget(content, maxTokens: tokens).0
    }
}

func durationMillis(_ duration: Duration) -> Int64 {
    let (seconds, attoseconds) = duration.components
    return seconds * 1000 + attoseconds / 1_000_000_000_000_000
}

/// Local stand-in for `codex_async_utils::backoff` (CodexProtocol cannot import that module).
func localBackoff(_ attempt: UInt64) -> Duration {
    let initialDelayMs = 200.0
    let backoffFactor = 2.0
    let exp = pow(backoffFactor, Double(attempt > 0 ? attempt - 1 : 0))
    let base = UInt64(initialDelayMs * exp)
    let jitter = Double.random(in: 0.9 ..< 1.1)
    return .milliseconds(Int64(Double(base) * jitter))
}

extension ExecToolCallOutput: Equatable {
    public static func == (lhs: ExecToolCallOutput, rhs: ExecToolCallOutput) -> Bool {
        lhs.exitCode == rhs.exitCode
            && lhs.stdout.text == rhs.stdout.text
            && lhs.stdout.truncatedAfterLines == rhs.stdout.truncatedAfterLines
            && lhs.stderr.text == rhs.stderr.text
            && lhs.stderr.truncatedAfterLines == rhs.stderr.truncatedAfterLines
            && lhs.aggregatedOutput.text == rhs.aggregatedOutput.text
            && lhs.aggregatedOutput.truncatedAfterLines == rhs.aggregatedOutput.truncatedAfterLines
            && lhs.duration == rhs.duration
            && lhs.timedOut == rhs.timedOut
    }
}
