//
//  common.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/common.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `tokio::sync::mpsc::Receiver` maps to `AsyncStream`. `serde_json::RawValue`
//  tools map to `JSONValue`. WebSocket request DTOs are kept for encode
//  compatibility; realtime transport is deferred. `W3cTraceContext.traceparent`
//  is non-optional in CodexProtocol, so empty strings are treated as absent.
//

import CodexProtocol
import Foundation

public let WS_REQUEST_HEADER_TRACEPARENT_CLIENT_METADATA_KEY = "ws_request_header_traceparent"
public let WS_REQUEST_HEADER_TRACESTATE_CLIENT_METADATA_KEY = "ws_request_header_tracestate"

/// Explicit per-request access selection using the Responses API wire values.
public struct AccessPrograms: Equatable, Sendable {
    public var cyber: String

    public init(cyber: String) {
        self.cyber = cyber
    }

    public init(_ program: CyberAccessProgram) {
        switch program {
        case .standard:
            self.cyber = "standard"
        case .daybreakBlue:
            self.cyber = "daybreak_blue"
        case .daybreakRed:
            self.cyber = "daybreak_red"
        }
    }
}

extension AccessPrograms: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cyber, forKey: .cyber)
    }

    private enum CodingKeys: String, CodingKey {
        case cyber
    }
}

/// Canonical input payload for the memory summarize endpoint.
public struct MemorySummarizeInput: Equatable, Sendable {
    public var model: String
    public var rawMemories: [RawMemory]
    public var reasoning: Reasoning?

    public init(model: String, rawMemories: [RawMemory], reasoning: Reasoning? = nil) {
        self.model = model
        self.rawMemories = rawMemories
        self.reasoning = reasoning
    }
}

extension MemorySummarizeInput: Encodable {
    private enum CodingKeys: String, CodingKey {
        case model
        case rawMemories = "traces"
        case reasoning
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(rawMemories, forKey: .rawMemories)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
    }
}

public struct RawMemory: Equatable, Sendable, Encodable {
    public var id: String
    public var metadata: RawMemoryMetadata
    public var items: [JSONValue]

    public init(id: String, metadata: RawMemoryMetadata, items: [JSONValue]) {
        self.id = id
        self.metadata = metadata
        self.items = items
    }
}

public struct RawMemoryMetadata: Equatable, Sendable, Encodable {
    public var sourcePath: String

    public init(sourcePath: String) {
        self.sourcePath = sourcePath
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath = "source_path"
    }
}

public struct MemorySummarizeOutput: Equatable, Sendable {
    public var rawMemory: String
    public var memorySummary: String

    public init(rawMemory: String, memorySummary: String) {
        self.rawMemory = rawMemory
        self.memorySummary = memorySummary
    }
}

extension MemorySummarizeOutput: Decodable {
    private enum CodingKeys: String, CodingKey {
        case rawMemory = "trace_summary"
        case rawMemoryAlias = "raw_memory"
        case memorySummary = "memory_summary"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .rawMemory) {
            rawMemory = value
        } else {
            rawMemory = try container.decode(String.self, forKey: .rawMemoryAlias)
        }
        memorySummary = try container.decode(String.self, forKey: .memorySummary)
    }
}

/// The latest server response ID received in this turn.
public struct ResponseId: Equatable, Sendable {
    public var value: String
    public init(_ value: String) { self.value = value }
}

public enum ResponseEvent: Equatable, Sendable {
    case created(responseId: String?)
    case safetyBuffering(SafetyBuffering)
    case outputItemDone(ResponseItem)
    case outputItemAdded(ResponseItem)
    case serverModel(String)
    case modelVerifications([ModelVerification])
    case turnModerationMetadata(TurnModerationMetadataEvent)
    case serverReasoningIncluded(Bool)
    case completed(
        responseId: String,
        tokenUsage: TokenUsage?,
        usageMetadata: ResponseUsageMetadata?,
        endTurn: Bool?
    )
    case outputTextDelta(String)
    case toolCallInputDelta(itemId: String, callId: String?, delta: String)
    case reasoningSummaryDelta(delta: String, summaryIndex: Int64)
    case reasoningSummaryDone(itemId: String, text: String, summaryIndex: Int64)
    case reasoningContentDelta(delta: String, contentIndex: Int64)
    case reasoningSummaryPartAdded(summaryIndex: Int64)
    case rateLimits(RateLimitSnapshot)
    case modelsEtag(String)
}

public struct SafetyBuffering: Equatable, Sendable {
    public var useCases: [String]
    public var reasons: [String]
    public var showBufferingUi: Bool
    public var fasterModel: String?

    public init(
        useCases: [String] = [],
        reasons: [String] = [],
        showBufferingUi: Bool = false,
        fasterModel: String? = nil
    ) {
        self.useCases = useCases
        self.reasons = reasons
        self.showBufferingUi = showBufferingUi
        self.fasterModel = fasterModel
    }
}

extension SafetyBuffering: Decodable {
    private enum CodingKeys: String, CodingKey {
        case useCases = "use_cases"
        case reasons
        case retryModel = "retry_model"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useCases = try container.decodeIfPresent([String].self, forKey: .useCases) ?? []
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
        showBufferingUi = false
        fasterModel = try container.decodeIfPresent(String.self, forKey: .retryModel)
    }
}

struct SafetyBufferingTreatment: Equatable, Sendable {
    var fasterModel: String?

    init(fasterModel: String? = nil) {
        self.fasterModel = fasterModel
    }
}

public enum ReasoningContext: String, Equatable, Sendable, Encodable {
    case auto
    case currentTurn = "current_turn"
    case allTurns = "all_turns"
}

public struct Reasoning: Equatable, Sendable {
    public var effort: ReasoningEffort?
    public var summary: ReasoningSummary?
    public var context: ReasoningContext?

    public init(
        effort: ReasoningEffort? = nil,
        summary: ReasoningSummary? = nil,
        context: ReasoningContext? = nil
    ) {
        self.effort = effort
        self.summary = summary
        self.context = context
    }
}

extension Reasoning: Encodable {
    private enum CodingKeys: String, CodingKey {
        case effort, summary, context
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let effort {
            if case .custom(let value) = effort, let numeric = UInt64(value) {
                try container.encode(numeric, forKey: .effort)
            } else {
                try container.encode(effort, forKey: .effort)
            }
        }
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(context, forKey: .context)
    }
}

public enum ReasoningSummaryDelivery: String, Equatable, Sendable, Encodable {
    case sequentialCutoff = "sequential_cutoff"
}

public struct StreamOptions: Equatable, Sendable, Encodable {
    public var reasoningSummaryDelivery: ReasoningSummaryDelivery

    public init(reasoningSummaryDelivery: ReasoningSummaryDelivery) {
        self.reasoningSummaryDelivery = reasoningSummaryDelivery
    }

    private enum CodingKeys: String, CodingKey {
        case reasoningSummaryDelivery = "reasoning_summary_delivery"
    }
}

public enum TextFormatType: String, Equatable, Sendable, Encodable {
    case jsonSchema = "json_schema"
}

public struct TextFormat: Equatable, Sendable, Encodable {
    public var type: TextFormatType
    public var strict: Bool
    public var schema: JSONValue
    public var name: String

    public init(
        type: TextFormatType = .jsonSchema,
        strict: Bool,
        schema: JSONValue,
        name: String
    ) {
        self.type = type
        self.strict = strict
        self.schema = schema
        self.name = name
    }
}

/// Controls the `text` field for the Responses API.
public struct TextControls: Equatable, Sendable, Encodable {
    public var verbosity: OpenAiVerbosity?
    public var format: TextFormat?

    public init(verbosity: OpenAiVerbosity? = nil, format: TextFormat? = nil) {
        self.verbosity = verbosity
        self.format = format
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(verbosity, forKey: .verbosity)
        try container.encodeIfPresent(format, forKey: .format)
    }

    private enum CodingKeys: String, CodingKey {
        case verbosity, format
    }
}

public enum OpenAiVerbosity: String, Equatable, Sendable, Encodable {
    case low
    case medium
    case high

    public init(_ verbosity: Verbosity) {
        switch verbosity {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        }
    }
}

/// Serialized tool definitions for Responses API requests.
public struct ResponsesApiTools: Equatable, Sendable {
    public var raw: JSONValue

    public init(_ raw: JSONValue) {
        self.raw = raw
    }

    public init(array: [JSONValue]) {
        self.raw = .array(array)
    }
}

extension ResponsesApiTools: Encodable {
    public func encode(to encoder: any Encoder) throws {
        try raw.encode(to: encoder)
    }
}

public struct ResponsesApiRequest: Equatable, Sendable {
    public var model: String
    public var instructions: String
    public var input: [ResponseItem]
    public var tools: ResponsesApiTools?
    public var toolChoice: String
    public var parallelToolCalls: Bool
    public var reasoning: Reasoning?
    public var store: Bool
    public var stream: Bool
    public var streamOptions: StreamOptions?
    public var include: [String]
    public var serviceTier: String?
    public var promptCacheKey: String?
    public var text: TextControls?
    public var clientMetadata: [String: String]?
    public var accessPrograms: AccessPrograms?

    public init(
        model: String,
        instructions: String = "",
        input: [ResponseItem],
        tools: ResponsesApiTools? = nil,
        toolChoice: String,
        parallelToolCalls: Bool,
        reasoning: Reasoning? = nil,
        store: Bool,
        stream: Bool,
        streamOptions: StreamOptions? = nil,
        include: [String] = [],
        serviceTier: String? = nil,
        promptCacheKey: String? = nil,
        text: TextControls? = nil,
        clientMetadata: [String: String]? = nil,
        accessPrograms: AccessPrograms? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.reasoning = reasoning
        self.store = store
        self.stream = stream
        self.streamOptions = streamOptions
        self.include = include
        self.serviceTier = serviceTier
        self.promptCacheKey = promptCacheKey
        self.text = text
        self.clientMetadata = clientMetadata
        self.accessPrograms = accessPrograms
    }
}

extension ResponsesApiRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case model, instructions, input, tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning, store, stream
        case streamOptions = "stream_options"
        case include
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case text
        case clientMetadata = "client_metadata"
        case accessPrograms = "access_programs"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        if !instructions.isEmpty {
            try container.encode(instructions, forKey: .instructions)
        }
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encode(toolChoice, forKey: .toolChoice)
        try container.encode(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(store, forKey: .store)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(streamOptions, forKey: .streamOptions)
        try container.encode(include, forKey: .include)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(clientMetadata, forKey: .clientMetadata)
        try container.encodeIfPresent(accessPrograms, forKey: .accessPrograms)
    }
}

public struct ResponseCreateWsRequest: Equatable, Sendable {
    public var model: String
    public var instructions: String
    public var previousResponseId: String?
    public var input: [ResponseItem]
    public var tools: JSONValue?
    public var toolChoice: String
    public var parallelToolCalls: Bool
    public var reasoning: Reasoning?
    public var store: Bool
    public var stream: Bool
    public var streamOptions: StreamOptions?
    public var include: [String]
    public var serviceTier: String?
    public var promptCacheKey: String?
    public var text: TextControls?
    public var generate: Bool?
    public var clientMetadata: [String: String]?
    public var accessPrograms: AccessPrograms?

    public init(_ request: ResponsesApiRequest) {
        self.model = request.model
        self.instructions = request.instructions
        self.previousResponseId = nil
        self.input = request.input
        self.tools = request.tools?.raw
        self.toolChoice = request.toolChoice
        self.parallelToolCalls = request.parallelToolCalls
        self.reasoning = request.reasoning
        self.store = request.store
        self.stream = request.stream
        self.streamOptions = request.streamOptions
        self.include = request.include
        self.serviceTier = request.serviceTier
        self.promptCacheKey = request.promptCacheKey
        self.text = request.text
        self.generate = nil
        self.clientMetadata = request.clientMetadata
        self.accessPrograms = request.accessPrograms
    }
}

extension ResponseCreateWsRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case model, instructions
        case previousResponseId = "previous_response_id"
        case input, tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning, store, stream
        case streamOptions = "stream_options"
        case include
        case serviceTier = "service_tier"
        case promptCacheKey = "prompt_cache_key"
        case text, generate
        case clientMetadata = "client_metadata"
        case accessPrograms = "access_programs"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        if !instructions.isEmpty {
            try container.encode(instructions, forKey: .instructions)
        }
        try container.encodeIfPresent(previousResponseId, forKey: .previousResponseId)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encode(toolChoice, forKey: .toolChoice)
        try container.encode(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(store, forKey: .store)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(streamOptions, forKey: .streamOptions)
        try container.encode(include, forKey: .include)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(generate, forKey: .generate)
        try container.encodeIfPresent(clientMetadata, forKey: .clientMetadata)
        try container.encodeIfPresent(accessPrograms, forKey: .accessPrograms)
    }
}

public enum ResponsesWsRequest: Equatable, Sendable {
    case responseCreate(ResponseCreateWsRequest)
}

extension ResponsesWsRequest: Encodable {
    private enum CodingKeys: String, CodingKey { case type }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .responseCreate(let request):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("response.create", forKey: .type)
            try request.encode(to: encoder)
        }
    }
}

public func responseCreateClientMetadata(
    _ clientMetadata: [String: String]?,
    trace: W3cTraceContext?
) -> [String: String]? {
    var clientMetadata = clientMetadata ?? [:]
    if let trace {
        if !trace.traceparent.isEmpty {
            clientMetadata[WS_REQUEST_HEADER_TRACEPARENT_CLIENT_METADATA_KEY] = trace.traceparent
        }
        if let tracestate = trace.tracestate, !tracestate.isEmpty {
            clientMetadata[WS_REQUEST_HEADER_TRACESTATE_CLIENT_METADATA_KEY] = tracestate
        }
    }
    return clientMetadata.isEmpty ? nil : clientMetadata
}

public func createTextParamForRequest(
    verbosity: Verbosity?,
    outputSchema: JSONValue?,
    outputSchemaStrict: Bool
) -> TextControls? {
    if verbosity == nil && outputSchema == nil {
        return nil
    }
    return TextControls(
        verbosity: verbosity.map(OpenAiVerbosity.init),
        format: outputSchema.map { schema in
            TextFormat(
                type: .jsonSchema,
                strict: outputSchemaStrict,
                schema: schema,
                name: "codex_output_schema"
            )
        }
    )
}

/// Server-assigned stream of `ResponseEvent` values.
public struct ResponseStream: Sendable {
    public var events: AsyncStream<Result<ResponseEvent, ApiError>>
    /// Server-assigned `x-request-id` response header, when present.
    public var upstreamRequestId: String?

    public init(
        events: AsyncStream<Result<ResponseEvent, ApiError>>,
        upstreamRequestId: String? = nil
    ) {
        self.events = events
        self.upstreamRequestId = upstreamRequestId
    }
}
