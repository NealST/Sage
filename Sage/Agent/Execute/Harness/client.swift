//
//  client.swift
//  CodexCore
//
//  Port of codex-rs/core/src/client.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  HTTP/SSE via URLSession + CodexAPI.ResponsesClient. WebSocket
//  transport, ChatGPT auth refresh, attestation, otel, and extension
//  interceptors wait. Auth is AuthProvider (Bearer API key).
//  Sage already has Agent/Model/ModelClient; this type lives in CodexCore.
//

import CodexAPI
import CodexAsyncUtils
import CodexModelProviderInfo
import CodexProtocol
import Foundation
import os

public let openaiBetaHeader = "OpenAI-Beta"
public let xCodexInstallationIdHeader = "x-codex-installation-id"
public let xCodexRoutingHintHeader = "x-codex-routing-hint"
public let xCodexTurnStateHeader = "x-codex-turn-state"
public let xCodexTurnMetadataHeader = "x-codex-turn-metadata"
public let xCodexParentThreadIdHeader = "x-codex-parent-thread-id"
public let xCodexWindowIdHeader = "x-codex-window-id"
public let xOpenaiMemgenRequestHeader = "x-openai-memgen-request"
public let xOpenaiSubagentHeader = "x-openai-subagent"
public let xResponsesapiIncludeTimingMetricsHeader = "x-responsesapi-include-timing-metrics"
let xOpenaiInternalCodexResponsesLiteHeader = "x-openai-internal-codex-responses-lite"

/// Session-scoped client for model-provider API calls.
public final class ModelClient: @unchecked Sendable {
    public let threadId: ThreadId
    public let providerInfo: ModelProviderInfo
    public let sessionSource: SessionSource
    public var modelVerbosity: Verbosity?
    public var contentItemKindsEnabled: Bool
    public var reasoningEffortOverrideEnabled: Bool
    public var enableRequestCompression: Bool
    public var includeTimingMetrics: Bool
    public var betaFeaturesHeader: String?
    public var concurrentReasoningSummariesEnabled: Bool
    public var promptCacheKeyOverride: String?
    public var codexResponsesHeaders: CodexResponsesHeaders?
    public var auth: SharedAuthProvider
    public var authMode: AuthMode?
    public var urlSession: URLSession
    public var requestContributors: [any ModelRequestContributor]
    public private(set) var disableWebsockets = true

    public init(
        threadId: ThreadId,
        providerInfo: ModelProviderInfo,
        sessionSource: SessionSource = .cli,
        auth: SharedAuthProvider? = nil,
        authMode: AuthMode? = .apiKey,
        modelVerbosity: Verbosity? = nil,
        contentItemKindsEnabled: Bool = false,
        reasoningEffortOverrideEnabled: Bool = false,
        enableRequestCompression: Bool = false,
        includeTimingMetrics: Bool = false,
        betaFeaturesHeader: String? = nil,
        concurrentReasoningSummariesEnabled: Bool = false,
        promptCacheKeyOverride: String? = nil,
        codexResponsesHeaders: CodexResponsesHeaders? = nil,
        urlSession: URLSession = .shared,
        requestContributors: [any ModelRequestContributor] = []
    ) {
        self.threadId = threadId
        self.providerInfo = providerInfo
        self.sessionSource = sessionSource
        self.modelVerbosity = modelVerbosity
        self.contentItemKindsEnabled = contentItemKindsEnabled
        self.reasoningEffortOverrideEnabled = reasoningEffortOverrideEnabled
        self.enableRequestCompression = enableRequestCompression
        self.includeTimingMetrics = includeTimingMetrics
        self.betaFeaturesHeader = betaFeaturesHeader
        self.concurrentReasoningSummariesEnabled = concurrentReasoningSummariesEnabled
        self.promptCacheKeyOverride = promptCacheKeyOverride
        self.codexResponsesHeaders = codexResponsesHeaders
        if let auth {
            self.auth = auth
        } else if let key = try? providerInfo.apiKey() {
            self.auth = BearerAuthProvider(apiKey: key)
        } else {
            self.auth = EmptyAuthProvider()
        }
        self.authMode = authMode
        self.urlSession = urlSession
        self.requestContributors = requestContributors
    }

    public func withPromptCacheKeyOverride(_ key: String?) -> ModelClient {
        promptCacheKeyOverride = key
        return self
    }

    public func withCodexResponsesHeaders(_ headers: CodexResponsesHeaders?) -> ModelClient {
        codexResponsesHeaders = headers
        return self
    }

    public func newSession() -> ModelClientSession {
        ModelClientSession(client: self)
    }

    public func responsesWebsocketEnabled() -> Bool {
        false
    }

    public func forceHttpFallback() -> Bool {
        let activated = !disableWebsockets
        disableWebsockets = true
        return activated
    }

    func promptCacheKey(_ responsesMetadata: CodexResponsesMetadata) -> String {
        if let promptCacheKeyOverride { return promptCacheKeyOverride }
        if case .internal = sessionSource, let parent = responsesMetadata.parentThreadId {
            return "\(sessionSourceInternalLabel()):\(parent)"
        }
        return responsesMetadata.sessionId
    }

    func responsesSessionId(_ metadata: CodexResponsesMetadata) -> String {
        if isNonRootAgent(sessionSource) {
            return metadata.sessionId
        }
        return promptCacheKey(metadata)
    }

    func reasoningEffortOverrideEnabled(_ modelInfo: ModelInfo) -> Bool {
        reasoningEffortOverrideEnabled
            && providerInfo.isOpenai()
            && modelInfo.supportsReasoningEffortUpdates
    }

    public func buildResponsesRequest(
        prompt: Prompt,
        modelInfo: ModelInfo,
        effort: ReasoningEffort?,
        summary: ReasoningSummary,
        serviceTier: String?,
        responsesMetadata: CodexResponsesMetadata,
        includeInternal: Bool
    ) -> ResponsesApiRequest {
        var input = prompt.getFormattedInputForRequest(modelInfo: modelInfo)
        if !reasoningEffortOverrideEnabled(modelInfo) {
            input.removeAll {
                if case .configurationUpdate = $0 { return true }
                return false
            }
        }
        let isOpenai = providerInfo.isOpenai()
        let instructions: String
        let tools: ResponsesApiTools?
        if modelInfo.useResponsesLite {
            var prefix: [ResponseItem] = []
            if !prompt.tools.isEmpty {
                prefix.append(.additionalTools(
                    id: ResponseItemId(new: "at"),
                    role: "developer",
                    tools: prompt.tools
                ))
            }
            if !prompt.baseInstructions.text.isEmpty {
                var item = BaseInstructionsFragment(text: prompt.baseInstructions.text).asResponseItem()
                if case .message(_, let role, let content, let phase, let meta) = item {
                    item = .message(
                        id: ResponseItemId(new: "msg"),
                        role: role,
                        content: content,
                        phase: phase,
                        internalChatMessageMetadataPassthrough: meta
                    )
                }
                prefix.append(item)
            }
            input.insert(contentsOf: prefix, at: 0)
            instructions = ""
            tools = nil
        } else {
            instructions = prompt.baseInstructions.text
            tools = prompt.tools.isEmpty ? nil : ResponsesApiTools(array: prompt.tools)
        }
        if !isOpenai {
            for index in input.indices {
                _ = input[index].modifyInternalChatMessageMetadata { $0 = nil }
            }
        }
        let reasoning = buildReasoning(modelInfo: modelInfo, effort: effort, summary: summary)
        let streamOptions = (concurrentReasoningSummariesEnabled && isOpenai && reasoning.summary != nil)
            ? StreamOptions(reasoningSummaryDelivery: .sequentialCutoff)
            : nil
        let verbosity: Verbosity?
        if modelInfo.supportVerbosity {
            verbosity = modelVerbosity ?? modelInfo.defaultVerbosity
        } else {
            verbosity = nil
        }
        let text = createTextParamForRequest(
            verbosity: verbosity,
            outputSchema: prompt.outputSchema,
            outputSchemaStrict: prompt.outputSchemaStrict
        )
        let resolvedTier = providerInfo.isAmazonBedrock()
            ? nil
            : modelInfo.serviceTierForRequest(serviceTier)
        if !includeInternal {
            for index in input.indices {
                input[index].clearToolResultMetadata()
            }
        }
        var request = ResponsesApiRequest(
            model: modelInfo.slug,
            instructions: instructions,
            input: input,
            tools: tools,
            toolChoice: "auto",
            parallelToolCalls: prompt.parallelToolCalls && !modelInfo.useResponsesLite,
            reasoning: reasoning,
            store: false,
            stream: true,
            streamOptions: streamOptions,
            include: ["reasoning.encrypted_content"],
            serviceTier: resolvedTier,
            promptCacheKey: promptCacheKey(responsesMetadata),
            text: text,
            clientMetadata: responsesMetadata.clientMetadata(includeInternal: includeInternal),
            accessPrograms: prompt.cyberAccessProgram.map(AccessPrograms.init)
        )
        if let bounded = boundedInput(message: request, input: request.input) {
            request.input = bounded
        }
        return request
    }

    func buildReasoning(
        modelInfo: ModelInfo,
        effort: ReasoningEffort?,
        summary: ReasoningSummary
    ) -> Reasoning {
        Reasoning(
            effort: effort ?? modelInfo.defaultReasoningLevel,
            summary: modelInfo.supportsReasoningSummaryParameter ? summary : nil,
            context: nil
        )
    }

    func apiProvider() throws -> Provider {
        try providerInfo.toApiProvider(authMode: authMode)
    }

    func sessionSourceInternalLabel() -> String {
        if case .internal(let source) = sessionSource {
            return source.rawValue
        }
        return "internal"
    }
}

/// Turn-scoped streaming session created from a ModelClient.
public final class ModelClientSession: @unchecked Sendable {
    public let client: ModelClient
    public let turnState = TurnStateBox()

    public init(client: ModelClient) {
        self.client = client
    }

    public func trySwitchFallbackTransport() -> Bool {
        client.forceHttpFallback()
    }

    public func stream(
        prompt: Prompt,
        modelInfo: ModelInfo,
        effort: ReasoningEffort? = nil,
        summary: ReasoningSummary = .auto,
        serviceTier: String? = nil,
        responsesMetadata: CodexResponsesMetadata
    ) async throws -> ResponseStream {
        try await streamResponsesAPI(
            prompt: prompt,
            modelInfo: modelInfo,
            effort: effort,
            summary: summary,
            serviceTier: serviceTier,
            responsesMetadata: responsesMetadata
        )
    }

    func streamResponsesAPI(
        prompt: Prompt,
        modelInfo: ModelInfo,
        effort: ReasoningEffort?,
        summary: ReasoningSummary,
        serviceTier: String?,
        responsesMetadata: CodexResponsesMetadata
    ) async throws -> ResponseStream {
        let provider = try client.apiProvider()
        let includeInternal = isInternalMetadataDestination(provider.baseUrl)
        var request = client.buildResponsesRequest(
            prompt: prompt,
            modelInfo: modelInfo,
            effort: effort,
            summary: summary,
            serviceTier: serviceTier,
            responsesMetadata: responsesMetadata,
            includeInternal: includeInternal
        )
        var options = ResponsesOptions(
            sessionId: client.responsesSessionId(responsesMetadata),
            threadId: client.threadId.description,
            sessionSource: client.sessionSource,
            extraHeaders: buildResponsesHeaders(
                betaFeaturesHeader: client.betaFeaturesHeader,
                turnState: turnState
            ),
            compression: client.enableRequestCompression ? .zstd : .none,
            turnState: turnState
        )
        if modelInfo.useResponsesLite {
            options.extraHeaders[xOpenaiInternalCodexResponsesLiteHeader] = "true"
        }
        if client.includeTimingMetrics {
            options.extraHeaders[xResponsesapiIncludeTimingMetricsHeader] = "true"
        }
        if let extra = client.codexResponsesHeaders, extra.model == modelInfo.slug {
            for (name, value) in extra.headers {
                options.extraHeaders[name.lowercased()] = value
            }
        }
        for (name, value) in responsesMetadata.compatibilityHeaders() {
            options.extraHeaders[name] = value
        }
        var metadata = request.clientMetadata
        let interceptors = prepareModelRequest(
            contributors: client.requestContributors,
            threadId: client.threadId.description,
            model: modelInfo.slug,
            kind: .generation,
            metadata: &metadata
        )
        request.clientMetadata = metadata
        let apiClient = ResponsesClient(
            urlSession: client.urlSession,
            provider: provider,
            auth: client.auth
        )
        do {
            let apiStream = try await apiClient.streamRequest(request, options: options)
            let intercepted = interceptStream(apiStream.events, interceptors: interceptors)
            return mapAPIStream(
                CodexAPI.ResponseStream(
                    events: intercepted,
                    upstreamRequestId: apiStream.upstreamRequestId
                )
            )
        } catch let error as ApiError {
            throw mapApiError(error)
        }
    }
}

func buildResponsesHeaders(betaFeaturesHeader: String?, turnState: TurnStateBox) -> [String: String] {
    var headers: [String: String] = [:]
    if let betaFeaturesHeader, !betaFeaturesHeader.isEmpty {
        headers["x-codex-beta-features"] = betaFeaturesHeader
    }
    if let state = turnState.get(), !state.isEmpty {
        headers[xCodexTurnStateHeader] = state
    }
    return headers
}

func isInternalMetadataDestination(_ baseURL: String) -> Bool {
    guard let url = URL(string: baseURL), url.scheme == "https", let host = url.host else {
        return false
    }
    return host == "api.openai.com" || host.hasSuffix(".chatgpt.com") || host == "chatgpt.com"
}

func isNonRootAgent(_ source: SessionSource) -> Bool {
    switch source {
    case .subAgent, .internal:
        return true
    default:
        return false
    }
}

func mapAPIStream(_ apiStream: CodexAPI.ResponseStream) -> ResponseStream {
    let dropped = CancellationToken()
    let events = AsyncStream<CodexResult<ResponseEvent>> { continuation in
        let task = Task {
            for await event in apiStream.events {
                if Task.isCancelled || dropped.isCancelled { break }
                switch event {
                case .success(let value):
                    continuation.yield(.success(value))
                case .failure(let error):
                    continuation.yield(.failure(mapApiError(error)))
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            dropped.cancel()
            task.cancel()
        }
    }
    return ResponseStream(
        events: events,
        consumerDropped: dropped,
        upstreamRequestId: apiStream.upstreamRequestId
    )
}

struct EmptyAuthProvider: AuthProvider {
    func addAuthHeaders(_ headers: inout [String: String]) {}
}
