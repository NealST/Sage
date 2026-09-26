//
//  responses.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/sse/responses.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `eventsource_stream` maps to an `event:` / `data:` / blank-line parser
//  over `URLSession.AsyncBytes`. `tokio::sync::mpsc` maps to `AsyncStream`.
//  Idle timeout uses `Task` racing. Tests are omitted. `OnceLock<String>`
//  turn-state is `TurnStateBox`.
//

import CodexProtocol
import Foundation

let X_REASONING_INCLUDED_HEADER = "x-reasoning-included"
let X_CODEX_TURN_STATE_HEADER = "x-codex-turn-state"
let OPENAI_MODEL_HEADER = "openai-model"
let REQUEST_ID_HEADER = "x-request-id"
let TRUSTED_ACCESS_FOR_CYBER_VERIFICATION = "trusted_access_for_cyber"

/// One-shot box standing in for `Arc<OnceLock<String>>`.
public final class TurnStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init() {}

    @discardableResult
    public func set(_ newValue: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard value == nil else { return false }
        value = newValue
        return true
    }

    public func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public struct SseEvent: Equatable, Sendable {
    public var event: String?
    public var data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

public func spawnResponseStream(
    headers: [String: String],
    bytes: URLSession.AsyncBytes,
    idleTimeout: Duration,
    telemetry: (any SseTelemetry)? = nil,
    turnState: TurnStateBox? = nil
) -> ResponseStream {
    let rateLimitSnapshots = parseAllRateLimits(headers)
    let modelsEtag = parseHeaderStr(headers, "x-models-etag")
    let serverModel = parseHeaderStr(headers, OPENAI_MODEL_HEADER)
    let reasoningIncluded = parseHeaderStr(headers, X_REASONING_INCLUDED_HEADER) != nil
    let upstreamRequestId = parseHeaderStr(headers, REQUEST_ID_HEADER)
    let safetyBufferingTreatment = treatmentFromHeaders(headers) ?? SafetyBufferingTreatment()
    if let turnState, let headerValue = parseHeaderStr(headers, X_CODEX_TURN_STATE_HEADER) {
        _ = turnState.set(headerValue)
    }

    let events = AsyncStream<Result<ResponseEvent, ApiError>> { continuation in
        let task = Task {
            if let model = serverModel {
                continuation.yield(.success(.serverModel(model)))
            }
            for snapshot in rateLimitSnapshots {
                continuation.yield(.success(.rateLimits(snapshot)))
            }
            if let etag = modelsEtag {
                continuation.yield(.success(.modelsEtag(etag)))
            }
            if reasoningIncluded {
                continuation.yield(.success(.serverReasoningIncluded(true)))
            }
            await processSseWithTreatment(
                bytes: bytes,
                continuation: continuation,
                idleTimeout: idleTimeout,
                telemetry: telemetry,
                safetyBufferingTreatment: safetyBufferingTreatment
            )
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
    return ResponseStream(events: events, upstreamRequestId: upstreamRequestId)
}

private struct FailedResponseError: Decodable {
    var type: String?
    var code: String?
    var message: String?
    var planType: String?
    var resetsAt: Int64?
    var misalignment: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type, code, message
        case planType = "plan_type"
        case resetsAt = "resets_at"
        case misalignment
    }
}

private struct ResponseCompleted: Decodable {
    var id: String
    var usage: ResponseCompletedUsage?
    var usageMetadata: ResponseUsageMetadata?
    var endTurn: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, usage
        case usageMetadata = "usage_metadata"
        case endTurn = "end_turn"
    }
}

private struct ResponseCompletedUsage: Decodable {
    var inputTokens: Int64
    var inputTokensDetails: ResponseCompletedInputTokensDetails?
    var outputTokens: Int64
    var outputTokensDetails: ResponseCompletedOutputTokensDetails?
    var totalTokens: Int64
    var codexRolloutBudgetUnits: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokens = "output_tokens"
        case outputTokensDetails = "output_tokens_details"
        case totalTokens = "total_tokens"
        case codexRolloutBudgetUnits = "codex_rollout_budget_units"
    }

    func toTokenUsage() -> TokenUsage {
        let inputDetails = inputTokensDetails ?? ResponseCompletedInputTokensDetails()
        return TokenUsage(
            inputTokens: inputTokens,
            cachedInputTokens: inputDetails.cachedTokens,
            cacheWriteInputTokens: inputDetails.cacheWriteTokens,
            outputTokens: outputTokens,
            reasoningOutputTokens: outputTokensDetails?.reasoningTokens ?? 0,
            totalTokens: totalTokens,
            codexRolloutBudgetUnits: codexRolloutBudgetUnits
        )
    }
}

private struct ResponseCompletedInputTokensDetails: Decodable {
    var cachedTokens: Int64
    var cacheWriteTokens: Int64

    init(cachedTokens: Int64 = 0, cacheWriteTokens: Int64 = 0) {
        self.cachedTokens = cachedTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    private enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
        case cacheWriteTokens = "cache_write_tokens"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cachedTokens = try container.decodeIfPresent(Int64.self, forKey: .cachedTokens) ?? 0
        cacheWriteTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheWriteTokens) ?? 0
    }
}

private struct ResponseCompletedOutputTokensDetails: Decodable {
    var reasoningTokens: Int64

    private enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
    }
}

public struct ResponsesStreamEvent: Equatable, Sendable {
    public var kind: String
    public var headers: JSONValue?
    public var metadata: JSONValue?
    public var response: JSONValue?
    public var error: JSONValue?
    public var item: JSONValue?
    public var itemId: String?
    public var callId: String?
    public var delta: String?
    public var text: String?
    public var summaryIndex: Int64?
    public var contentIndex: Int64?
    public var safetyBuffering: JSONValue?

    public init(
        kind: String,
        headers: JSONValue? = nil,
        metadata: JSONValue? = nil,
        response: JSONValue? = nil,
        error: JSONValue? = nil,
        item: JSONValue? = nil,
        itemId: String? = nil,
        callId: String? = nil,
        delta: String? = nil,
        text: String? = nil,
        summaryIndex: Int64? = nil,
        contentIndex: Int64? = nil,
        safetyBuffering: JSONValue? = nil
    ) {
        self.kind = kind
        self.headers = headers
        self.metadata = metadata
        self.response = response
        self.error = error
        self.item = item
        self.itemId = itemId
        self.callId = callId
        self.delta = delta
        self.text = text
        self.summaryIndex = summaryIndex
        self.contentIndex = contentIndex
        self.safetyBuffering = safetyBuffering
    }
}

extension ResponsesStreamEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case headers, metadata, response, error, item
        case itemId = "item_id"
        case callId = "call_id"
        case delta, text
        case summaryIndex = "summary_index"
        case contentIndex = "content_index"
        case safetyBuffering = "safety_buffering"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        headers = try container.decodeIfPresent(JSONValue.self, forKey: .headers)
        metadata = try container.decodeIfPresent(JSONValue.self, forKey: .metadata)
        response = try container.decodeIfPresent(JSONValue.self, forKey: .response)
        error = try container.decodeIfPresent(JSONValue.self, forKey: .error)
        item = try container.decodeIfPresent(JSONValue.self, forKey: .item)
        itemId = try container.decodeIfPresent(String.self, forKey: .itemId)
        callId = try container.decodeIfPresent(String.self, forKey: .callId)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        summaryIndex = try container.decodeIfPresent(Int64.self, forKey: .summaryIndex)
        contentIndex = try container.decodeIfPresent(Int64.self, forKey: .contentIndex)
        if container.contains(.safetyBuffering) {
            safetyBuffering = try container.decode(JSONValue.self, forKey: .safetyBuffering)
        } else {
            safetyBuffering = nil
        }
    }
}

extension ResponsesStreamEvent {
    /// Precedence: `response.headers` then top-level `headers`.
    public func responseModel() -> String? {
        if let model = response?.objectValue?["headers"].flatMap(headerOpenaiModelValueFromJson) {
            return model
        }
        return headers.flatMap(headerOpenaiModelValueFromJson)
    }

    func turnState() -> String? {
        guard kind == "response.metadata" else { return nil }
        return headers.flatMap(headerTurnStateValueFromJson)
    }

    func modelVerifications() -> [ModelVerification]? {
        guard kind == "response.metadata" else { return nil }
        return metadata
            .flatMap { $0.objectValue?["openai_verification_recommendation"] }
            .flatMap(modelVerificationsFromJsonValue)
    }

    func turnModerationMetadata() -> TurnModerationMetadataEvent? {
        guard kind == "response.metadata" else { return nil }
        guard let value = metadata?.objectValue?["openai_chatgpt_moderation_metadata"] else {
            return nil
        }
        return TurnModerationMetadataEvent(metadata: value)
    }

    func safetyBuffering(treatment: SafetyBufferingTreatment) -> SafetyBuffering? {
        let value: JSONValue?
        if let safetyBuffering {
            value = safetyBuffering
        } else if kind == "response.metadata",
                  let metadata,
                  metadata.objectValue?["type"]?.stringValue == "safety_buffering"
        {
            value = metadata
        } else {
            value = nil
        }
        guard let value, let object = value.objectValue else { return nil }
        let retryModelPresent = object.keys.contains("retry_model")
        guard var buffering = decodeJSON(SafetyBuffering.self, from: value) else { return nil }
        buffering.showBufferingUi = true
        if !retryModelPresent {
            buffering.fasterModel = treatment.fasterModel
        }
        return buffering
    }
}

private func headerOpenaiModelValueFromJson(_ value: JSONValue) -> String? {
    guard let headers = value.objectValue else { return nil }
    return headers.first { name, _ in
        name.caseInsensitiveCompare("openai-model") == .orderedSame
            || name.caseInsensitiveCompare("x-openai-model") == .orderedSame
    }.flatMap { jsonValueAsString($0.value) }
}

private func headerTurnStateValueFromJson(_ value: JSONValue) -> String? {
    guard let headers = value.objectValue else { return nil }
    return headers.first { name, _ in
        name.caseInsensitiveCompare(X_CODEX_TURN_STATE_HEADER) == .orderedSame
    }.flatMap { jsonValueAsString($0.value) }
}

private func modelVerificationsFromJsonValue(_ value: JSONValue) -> [ModelVerification]? {
    var verifications: [ModelVerification] = []
    if let items = value.arrayValue {
        for item in items {
            guard let raw = item.stringValue,
                  let verification = parseModelVerification(raw),
                  !verifications.contains(verification)
            else { continue }
            verifications.append(verification)
        }
    }
    return verifications.isEmpty ? nil : verifications
}

private func parseModelVerification(_ value: String) -> ModelVerification? {
    switch value {
    case TRUSTED_ACCESS_FOR_CYBER_VERIFICATION:
        return .trustedAccessForCyber
    default:
        return nil
    }
}

private func jsonValueAsString(_ value: JSONValue) -> String? {
    switch value {
    case .string(let value):
        return value
    case .array(let items):
        return items.first.flatMap(jsonValueAsString)
    default:
        return nil
    }
}

public enum ResponsesEventError: Error, Equatable, Sendable {
    case api(ApiError)

    public func intoApiError() -> ApiError {
        switch self {
        case .api(let error):
            return error
        }
    }
}

public func processResponsesEvent(_ event: ResponsesStreamEvent) throws -> ResponseEvent? {
    switch event.kind {
    case "error":
        if let error = event.error.flatMap(parseFlexUnavailable) {
            throw error
        }
    case "response.output_item.done":
        if let itemVal = event.item, let item = decodeJSON(ResponseItem.self, from: itemVal) {
            return .outputItemDone(item)
        }
    case "response.output_text.delta":
        if let delta = event.delta {
            return .outputTextDelta(delta)
        }
    case "response.custom_tool_call_input.delta":
        if let delta = event.delta, let itemId = event.itemId ?? event.callId {
            return .toolCallInputDelta(itemId: itemId, callId: event.callId, delta: delta)
        }
    case "response.reasoning_summary_text.delta":
        if let delta = event.delta, let summaryIndex = event.summaryIndex {
            return .reasoningSummaryDelta(delta: delta, summaryIndex: summaryIndex)
        }
    case "response.reasoning_summary_text.done":
        if let itemId = event.itemId, let text = event.text, let summaryIndex = event.summaryIndex {
            return .reasoningSummaryDone(itemId: itemId, text: text, summaryIndex: summaryIndex)
        }
    case "response.reasoning_text.delta":
        if let delta = event.delta, let contentIndex = event.contentIndex {
            return .reasoningContentDelta(delta: delta, contentIndex: contentIndex)
        }
    case "response.created":
        if let response = event.response {
            let responseId = response.objectValue?["id"]?.stringValue
            return .created(responseId: responseId)
        }
    case "response.failed":
        if let respVal = event.response {
            var responseError = ApiError.stream("response.failed event received")
            if let error = respVal.objectValue?["error"].flatMap(parseFlexUnavailable) {
                throw error
            }
            if let errorValue = respVal.objectValue?["error"],
               let error = decodeJSON(FailedResponseError.self, from: errorValue)
            {
                if isContextWindowError(error) {
                    responseError = .contextWindowExceeded
                } else if isQuotaExceededError(error) {
                    responseError = .quotaExceeded
                } else if isUsageNotIncluded(error) {
                    responseError = .usageNotIncluded
                } else if isCyberPolicyError(error) {
                    responseError = .cyberPolicy(message: cyberPolicyMessage(error.message))
                } else if error.code == "bio_policy" {
                    let message = error.message
                        .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                        ?? "This content was flagged for possible biological risk."
                    responseError = .bioPolicy(message: message)
                } else if error.code == "misalignment_policy_violation" {
                    let message = error.message
                        .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                        ?? "This request was blocked due to a misalignment policy violation."
                    let misalignment = error.misalignment.flatMap { details in
                        decodeJSON(MisalignmentErrorDetails.self, from: details)
                    }
                    responseError = .misalignmentPolicyViolation(
                        message: message,
                        misalignment: misalignment
                    )
                } else if error.code == "invalid_prompt" {
                    responseError = .invalidPrompt(message: error.message ?? "Invalid request.")
                } else if isServerOverloadedError(error) {
                    responseError = .serverOverloaded(retryAfter: nil)
                } else {
                    let retryAfter = tryParseRetryDelay(error).flatMap { RetryAfter.fromDelay($0) }
                    let message = error.message ?? ""
                    switch error.code {
                    case "rate_limit_exceeded", "slow_down":
                        responseError = .rateLimitExceeded(message: message, retryAfter: retryAfter)
                    default:
                        responseError = .retryable(message: message, retryAfter: retryAfter)
                    }
                }
            }
            throw responseError
        }
        throw ApiError.stream("response.failed event received")
    case "response.incomplete":
        let reason = event.response?
            .objectValue?["incomplete_details"]?
            .objectValue?["reason"]?
            .stringValue ?? "unknown"
        throw ApiError.stream("Incomplete response returned, reason: \(reason)")
    case "response.completed":
        if let respVal = event.response {
            let metadata = respVal.objectValue?["usage"].flatMap { usage -> JSONValue? in
                if case .null = usage { return nil }
                return usage
            }
            do {
                var resp = try decodeJSONThrowing(ResponseCompleted.self, from: respVal)
                if let metadata {
                    if resp.usageMetadata == nil {
                        resp.usageMetadata = ResponseUsageMetadata()
                    }
                    resp.usageMetadata?.metadata = metadata
                }
                return .completed(
                    responseId: resp.id,
                    tokenUsage: resp.usage?.toTokenUsage(),
                    usageMetadata: resp.usageMetadata,
                    endTurn: resp.endTurn
                )
            } catch {
                throw ApiError.stream("failed to parse ResponseCompleted: \(error)")
            }
        }
    case "response.output_item.added":
        if let itemVal = event.item, let item = decodeJSON(ResponseItem.self, from: itemVal) {
            return .outputItemAdded(item)
        }
    case "response.reasoning_summary_part.added":
        if let summaryIndex = event.summaryIndex {
            return .reasoningSummaryPartAdded(summaryIndex: summaryIndex)
        }
    case "codex.response.metadata",
         "response.content_part.added",
         "response.content_part.done",
         "response.custom_tool_call_input.done",
         "response.function_call_arguments.delta",
         "response.function_call_arguments.done",
         "response.in_progress",
         "response.metadata",
         "response.output_text.done",
         "response.reasoning_summary_part.done",
         "responsesapi.websocket_timing":
        break
    default:
        if event.kind.hasSuffix(".delta") {
            break
        }
    }
    return nil
}

func processSseWithTreatment(
    bytes: URLSession.AsyncBytes,
    continuation: AsyncStream<Result<ResponseEvent, ApiError>>.Continuation,
    idleTimeout: Duration,
    telemetry: (any SseTelemetry)?,
    safetyBufferingTreatment: SafetyBufferingTreatment
) async {
    var responseError: ApiError?
    var lastServerModel: String?
    let parser = SseByteParser()

    let reader = SseByteReader(bytes: bytes)
    while true {
        if Task.isCancelled { return }
        let start = ContinuousClock.now
        let poll: Result<SseEvent?, Error>
        do {
            let event = try await withIdleTimeout(idleTimeout) {
                try await nextSseEvent(parser: parser, reader: reader)
            }
            poll = .success(event)
        } catch is IdleTimeoutError {
            poll = .failure(IdleTimeoutError())
        } catch {
            poll = .failure(error)
        }
        telemetry?.onSsePoll(pollResult(poll), duration: ContinuousClock.now - start)

        switch poll {
        case .failure(let error) where error is IdleTimeoutError:
            continuation.yield(.failure(.stream("idle timeout waiting for SSE")))
            return
        case .failure(let error):
            continuation.yield(.failure(.stream(String(describing: error))))
            return
        case .success(nil):
            continuation.yield(
                .failure(
                    responseError
                        ?? .stream("stream closed before response.completed")
                )
            )
            return
        case .success(let event?):
            if await handleParsedSseEvent(
                event,
                continuation: continuation,
                lastServerModel: &lastServerModel,
                responseError: &responseError,
                safetyBufferingTreatment: safetyBufferingTreatment
            ) {
                return
            }
        }
    }
}

private final class SseByteReader: @unchecked Sendable {
    private var iterator: URLSession.AsyncBytes.Iterator

    init(bytes: URLSession.AsyncBytes) {
        self.iterator = bytes.makeAsyncIterator()
    }

    func next() async throws -> UInt8? {
        try await iterator.next()
    }
}

private func nextSseEvent(
    parser: SseByteParser,
    reader: SseByteReader
) async throws -> SseEvent? {
    if let queued = parser.nextEvent() {
        return queued
    }
    while let byte = try await reader.next() {
        parser.append(byte)
        if let event = parser.nextEvent() {
            return event
        }
    }
    let remaining = parser.finish()
    if remaining.isEmpty {
        return nil
    }
    remaining.dropFirst().forEach { parser.enqueue($0) }
    return remaining.first
}

@discardableResult
private func handleParsedSseEvent(
    _ sse: SseEvent,
    continuation: AsyncStream<Result<ResponseEvent, ApiError>>.Continuation,
    lastServerModel: inout String?,
    responseError: inout ApiError?,
    safetyBufferingTreatment: SafetyBufferingTreatment
) async -> Bool {
    guard let data = sse.data.data(using: .utf8),
          let event = try? JSONDecoder().decode(ResponsesStreamEvent.self, from: data)
    else {
        return false
    }

    let modelVerifications = event.modelVerifications()
    let turnModerationMetadata = event.turnModerationMetadata()
    let safetyBuffering = event.safetyBuffering(treatment: safetyBufferingTreatment)

    if let model = event.responseModel(), lastServerModel != model {
        continuation.yield(.success(.serverModel(model)))
        lastServerModel = model
    }
    if let verifications = modelVerifications {
        continuation.yield(.success(.modelVerifications(verifications)))
    }
    if let metadata = turnModerationMetadata {
        continuation.yield(.success(.turnModerationMetadata(metadata)))
    }
    if let buffering = safetyBuffering {
        continuation.yield(.success(.safetyBuffering(buffering)))
    }

    do {
        if let processed = try processResponsesEvent(event) {
            let isCompleted: Bool
            if case .completed = processed {
                isCompleted = true
            } else {
                isCompleted = false
            }
            continuation.yield(.success(processed))
            return isCompleted
        }
    } catch let error as ApiError {
        if case .flexUnavailable = error {
            continuation.yield(.failure(error))
            return true
        }
        responseError = error
    } catch {
        responseError = .stream(String(describing: error))
    }
    return false
}

private struct IdleTimeoutError: Error {}

private func pollResult(_ poll: Result<SseEvent?, Error>) -> SsePollResult {
    switch poll {
    case .success(.some):
        return .event
    case .success(.none):
        return .ended
    case .failure(is IdleTimeoutError):
        return .idleTimeout
    case .failure(let error):
        return .transportError(String(describing: error))
    }
}

private func withIdleTimeout<T: Sendable>(
    _ timeout: Duration,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await body()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw IdleTimeoutError()
        }
        guard let value = try await group.next() else {
            throw IdleTimeoutError()
        }
        group.cancelAll()
        return value
    }
}

/// Incremental `event:` / `data:` / blank-line SSE framer.
final class SseByteParser: @unchecked Sendable {
    private var buffer = Data()
    private var eventName: String?
    private var dataLines: [String] = []
    private var ready: [SseEvent] = []

    var remainder: Data { buffer }

    func append(_ byte: UInt8) {
        if byte == 0x0A {
            consumeLine()
        } else {
            buffer.append(byte)
        }
    }

    func nextEvent() -> SseEvent? {
        ready.isEmpty ? nil : ready.removeFirst()
    }

    func enqueue(_ event: SseEvent) {
        ready.append(event)
    }

    func finish() -> [SseEvent] {
        if !buffer.isEmpty {
            consumeLine()
        }
        if eventName != nil || !dataLines.isEmpty {
            flushEvent()
        }
        let events = ready
        ready.removeAll()
        return events
    }

    private func consumeLine() {
        if buffer.last == 0x0D {
            buffer.removeLast()
        }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        if line.isEmpty {
            flushEvent()
            return
        }
        if line.hasPrefix(":") {
            return
        }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return
        }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") {
                value = String(value.dropFirst())
            }
            dataLines.append(value)
            return
        }
    }

    private func flushEvent() {
        guard eventName != nil || !dataLines.isEmpty else { return }
        ready.append(SseEvent(event: eventName, data: dataLines.joined(separator: "\n")))
        eventName = nil
        dataLines.removeAll(keepingCapacity: true)
    }
}

private func tryParseRetryDelay(_ err: FailedResponseError) -> Duration? {
    guard err.code == "rate_limit_exceeded" || err.code == "slow_down" else {
        return nil
    }
    guard let message = err.message,
          let match = rateLimitRegex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
          let valueRange = Range(match.range(at: 1), in: message),
          let unitRange = Range(match.range(at: 2), in: message),
          let value = Double(message[valueRange])
    else { return nil }
    let unit = message[unitRange].lowercased()
    if unit == "s" || unit.hasPrefix("second") {
        return .seconds(value)
    }
    if unit == "ms" {
        return .milliseconds(Int64(value))
    }
    return nil
}

private let rateLimitRegex: NSRegularExpression = {
    // (?i)try again in\s*(\d+(?:\.\d+)?)\s*(s|ms|seconds?)
    try! NSRegularExpression(
        pattern: "(?i)try again in\\s*(\\d+(?:\\.\\d+)?)\\s*(s|ms|seconds?)"
    )
}()

private func isContextWindowError(_ error: FailedResponseError) -> Bool {
    error.code == "context_length_exceeded"
}

private func isQuotaExceededError(_ error: FailedResponseError) -> Bool {
    switch error.code {
    case "insufficient_quota",
         "credit_balance_exhausted",
         "organization_spend_limit_exceeded",
         "project_spend_limit_exceeded":
        return true
    default:
        return false
    }
}

private func isUsageNotIncluded(_ error: FailedResponseError) -> Bool {
    error.code == "usage_not_included"
}

private func isCyberPolicyError(_ error: FailedResponseError) -> Bool {
    error.code == "cyber_policy"
}

private func isServerOverloadedError(_ error: FailedResponseError) -> Bool {
    error.code == "server_is_overloaded"
}

private func cyberPolicyFallbackMessage() -> String {
    "This request has been flagged for possible cybersecurity risk."
}

private func cyberPolicyMessage(_ message: String?) -> String {
    message
        .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        ?? cyberPolicyFallbackMessage()
}

private func decodeJSON<T: Decodable>(_ type: T.Type, from value: JSONValue) -> T? {
    try? decodeJSONThrowing(type, from: value)
}

private func decodeJSONThrowing<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = Data(value.encodedString().utf8)
    return try JSONDecoder().decode(type, from: data)
}
