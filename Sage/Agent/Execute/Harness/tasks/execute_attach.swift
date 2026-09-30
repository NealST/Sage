//
//  execute_attach.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  Maps AgentSessionState events onto a harness Session so RegularTask
//  can attach rust RegularTask → runTurn. Live Execute opts in through
//  `useHarnessRunTurn` (Settings / ModelSettings). The Responses client
//  is leased onto that Session and reused for later samples.
//

import CodexAPI
import CodexCore
import CodexModelProviderInfo
import CodexProtocol
import Foundation

enum ExecuteHarnessAttach {
    struct Snapshot: Equatable, Sendable {
        var history: [ResponseItem]
        var input: [SessionTurnInput]
        var cwd: String
        var model: String
        var allowsMutation: Bool
    }

    static func snapshot(
        events: [AgentEvent],
        cwd: String,
        model: String,
        allowsMutation: Bool = false
    ) -> Snapshot {
        let lastUserIndex = events.lastIndex(where: { $0.kind == .userInput })
        let prior: ArraySlice<AgentEvent>
        let turnEvent: AgentEvent?
        if let lastUserIndex {
            prior = events[..<lastUserIndex]
            turnEvent = events[lastUserIndex]
        } else {
            prior = events[...]
            turnEvent = nil
        }
        return Snapshot(
            history: prior.flatMap(responseItems(from:)),
            input: turnEvent.map { [TurnInputBuilder.user(userContents(from: $0))] } ?? [],
            cwd: cwd,
            model: model,
            allowsMutation: allowsMutation
        )
    }

    static func makeSession(
        history: [ResponseItem],
        threadId: ThreadId = ThreadId()
    ) -> Session {
        let session = Session(threadId: threadId)
        if !history.isEmpty {
            session.state.recordItems(history)
        }
        return session
    }

    /// One Responses client for a thread. Same base URL and key keep the
    /// client (and its thread id). A key or URL change builds a new client
    /// on that same thread id. Empty credentials return nil.
    struct ResponsesClientLease: Sendable {
        var client: CodexCore.ModelClient
        var baseURL: String
        var apiKey: String
    }

    static func responsesClient(
        baseURL: String,
        apiKey: String,
        threadId: ThreadId
    ) -> CodexCore.ModelClient {
        let provider = ModelProviderInfo(name: "sage", baseUrl: baseURL, wireApi: .responses)
        return CodexCore.ModelClient(
            threadId: threadId,
            providerInfo: provider,
            auth: BearerAuthProvider(apiKey: apiKey),
            authMode: AuthMode.apiKey
        )
    }

    static func leaseResponsesClient(
        existing: ResponsesClientLease?,
        baseURL: String,
        apiKey: String
    ) -> ResponsesClientLease? {
        guard !baseURL.isEmpty, !apiKey.isEmpty else { return nil }
        if let existing, existing.baseURL == baseURL, existing.apiKey == apiKey {
            return existing
        }
        let threadId = existing?.client.threadId ?? ThreadId()
        return ResponsesClientLease(
            client: responsesClient(baseURL: baseURL, apiKey: apiKey, threadId: threadId),
            baseURL: baseURL,
            apiKey: apiKey
        )
    }

    static func responsesMetadata(session: Session, turn: TurnContext?) -> CodexResponsesMetadata {
        var metadata = CodexResponsesMetadata(
            installationId: session.installationId,
            sessionId: turn?.sessionId.description ?? session.threadId.description,
            threadId: session.threadId.description,
            windowId: session.currentWindowId()
        )
        metadata.turnId = turn?.subId
        metadata.requestKind = .turn
        metadata.parentThreadId = session.state.sessionConfiguration.parentThreadId
        return metadata
    }

    static func makeTurnContext(cwd: String, model: String, allowsMutation: Bool) -> TurnContext {
        TurnContext(
            cwd: cwd,
            model: model,
            sandboxPolicy: allowsMutation
                ? .workspaceWrite(
                    writableRoots: [],
                    networkAccess: true,
                    excludeTmpdirEnvVar: false,
                    excludeSlashTmp: false
                )
                : .readOnly(networkAccess: false),
            permissionProfile: allowsMutation ? .workspaceWrite() : .readOnly(),
            environment: TurnEnvironment(cwd: cwd)
        )
    }

    static func samplingResult(from turn: ModelTurn) throws -> SamplingRequestResult {
        if !turn.toolCalls.isEmpty {
            throw CodexErr.fatal("use responseStream(from:) so runTurn can dispatch tools")
        }
        let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SamplingRequestResult(needsFollowUp: false, lastAgentMessage: text)
    }

    static func responseStream(from turn: ModelTurn, endTurn: Bool = true) -> CodexCore.ResponseStream {
        var events: [CodexResult<ResponseEvent>] = []
        let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            events.append(
                .success(.outputItemDone(.message(
                    id: nil,
                    role: "assistant",
                    content: [.outputText(text: text)],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                )))
            )
        }
        for call in turn.toolCalls {
            events.append(
                .success(.outputItemDone(.functionCall(
                    id: nil,
                    name: call.name,
                    namespace: nil,
                    arguments: call.argumentsJSON,
                    encryptedFunctionArgs: nil,
                    callId: call.id,
                    internalChatMessageMetadataPassthrough: nil
                )))
            )
        }
        events.append(
            .success(.completed(
                responseId: "sage-execute",
                tokenUsage: nil,
                usageMetadata: nil,
                endTurn: endTurn
            ))
        )
        return makeResponseStream(events)
    }

    static func responseItems(from event: AgentEvent) -> [ResponseItem] {
        switch event.kind {
        case .systemInstruction:
            return []
        case .userInput:
            return [
                .message(
                    id: nil,
                    role: "user",
                    content: userContents(from: event).map(contentItem(from:)),
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                ),
            ]
        case .assistantResponse:
            var items: [ResponseItem] = []
            let text = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                items.append(
                    .message(
                        id: nil,
                        role: "assistant",
                        content: [.outputText(text: text)],
                        phase: nil,
                        internalChatMessageMetadataPassthrough: nil
                    )
                )
            }
            for call in event.toolCalls ?? [] {
                items.append(
                    .functionCall(
                        id: nil,
                        name: call.name,
                        namespace: nil,
                        arguments: call.argumentsJSON,
                        encryptedFunctionArgs: nil,
                        callId: call.id,
                        internalChatMessageMetadataPassthrough: nil
                    )
                )
            }
            return items
        case .toolResult:
            return [
                .functionCallOutput(
                    id: nil,
                    callId: event.toolCallID,
                    name: nil,
                    namespace: nil,
                    output: .fromText(event.content),
                    internalChatMessageMetadataPassthrough: nil
                ),
            ]
        }
    }

    static func userContents(from event: AgentEvent) -> [UserInput] {
        var contents: [UserInput] = []
        let text = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            contents.append(.text(text: event.content, textElements: []))
        }
        for attachment in event.attachments {
            switch attachment.kind {
            case .image:
                contents.append(.localImage(path: attachment.path, detail: nil))
            case .file, .folder:
                contents.append(.text(text: attachment.promptLine, textElements: []))
            }
        }
        if contents.isEmpty {
            contents.append(.text(text: event.content, textElements: []))
        }
        return contents
    }

    /// Chat-completions conversation for a harness `Prompt`. System instructions
    /// stay on the Sage prefix; this is only the turn history `runTurn` built.
    static func agentEvents(from items: [ResponseItem]) -> [AgentEvent] {
        var events: [AgentEvent] = []
        var pendingText = ""
        var pendingCalls: [ToolCallRecord] = []

        func flushAssistant() {
            let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty || !pendingCalls.isEmpty else {
                pendingText = ""
                pendingCalls = []
                return
            }
            events.append(
                AgentEvent(
                    kind: .assistantResponse,
                    content: text,
                    toolCalls: pendingCalls.isEmpty ? nil : pendingCalls
                )
            )
            pendingText = ""
            pendingCalls = []
        }

        for item in items {
            switch item {
            case .message(_, let role, let content, _, _):
                let text = plainText(from: content)
                if role == "user" || role == "system" || role == "developer" {
                    flushAssistant()
                    let kind: AgentEventKind = role == "user" ? .userInput : .systemInstruction
                    if !text.isEmpty {
                        events.append(AgentEvent(kind: kind, content: text))
                    }
                } else {
                    if !pendingCalls.isEmpty {
                        flushAssistant()
                    }
                    if !text.isEmpty {
                        pendingText = pendingText.isEmpty ? text : pendingText + "\n" + text
                    }
                }

            case .functionCall(_, let name, _, let arguments, _, let callId, _):
                pendingCalls.append(
                    ToolCallRecord(id: callId, name: name, argumentsJSON: arguments)
                )

            case .functionCallOutput(_, let callId, _, _, let output, _):
                flushAssistant()
                events.append(
                    AgentEvent(
                        kind: .toolResult,
                        content: output.body.toText() ?? output.description,
                        toolCallID: callId
                    )
                )

            default:
                break
            }
        }
        flushAssistant()
        return events
    }

    /// Responses function schemas for the prompt `buildPrompt` already assembled.
    static func responsesTools(_ tools: [ToolDefinition]) -> [CodexProtocol.JSONValue] {
        tools.map(responsesTool)
    }

    /// One `/responses` stream, kept so a collected sample can be replayed.
    /// `nil` call-id filter keeps every event. Live turns use `liveResponses`
    /// and hold function calls until HUD admission.
    struct ResponsesSample: Sendable {
        var turn: ModelTurn
        var events: [CodexResult<ResponseEvent>]
    }

    /// What to do with function calls once the provider response has completed.
    enum ResponsesToolGate: Sendable {
        /// Emit function calls whose id is in the set, then the original `completed`.
        case admit(Set<String>)
        /// Drop function calls and finish with `endTurn: false`.
        case followUpWithoutTools
        /// Drop function calls and finish the sampling request.
        case finishWithoutTools
    }

    /// Samples the prompt `runTurn` built, through the open `ModelClientSession`.
    /// A 404 means this host has no Responses route.
    static func sampleResponses(
        prompt: Prompt,
        clientSession: ModelClientSession,
        modelInfo: ModelInfo,
        metadata: CodexResponsesMetadata
    ) async throws -> ResponsesSample {
        let stream = try await clientSession.stream(
            prompt: prompt,
            modelInfo: modelInfo,
            responsesMetadata: metadata
        )
        return try await collectResponses(from: stream)
    }

    static func collectResponses(from stream: CodexCore.ResponseStream) async throws -> ResponsesSample {
        var events: [CodexResult<ResponseEvent>] = []
        var builder = ResponseAccumulator()
        for await event in stream.events {
            let value: ResponseEvent
            switch event {
            case .success(let event):
                value = event
            case .failure(let error):
                throw error
            }
            events.append(.success(value))
            builder.observe(value)
            if case .completed = value {
                return ResponsesSample(turn: builder.turn, events: events)
            }
        }
        throw CodexErr.stream("stream closed before response.completed")
    }

    /// Forwards provider events as they arrive. Function calls and `completed`
    /// wait until `decide` runs, so HUD can drop refused calls before `runTurn`
    /// dispatches them. The first event is inspected here: a 404 still throws
    /// so the caller can fall back to chat completions.
    static func liveResponses(
        _ upstream: CodexCore.ResponseStream,
        decide: @escaping (ModelTurn) async -> ResponsesToolGate
    ) async throws -> CodexCore.ResponseStream {
        let prefix = ResponsePrefix()
        let (bridged, continuation) = AsyncStream<CodexResult<ResponseEvent>>.makeStream()
        let finish = OnceFinish(continuation)
        let reader = Task {
            var sawFirst = false
            defer { finish.finish() }
            for await event in upstream.events {
                if Task.isCancelled { return }
                continuation.yield(event)
                if !sawFirst {
                    sawFirst = true
                    await prefix.publish(event)
                }
            }
            if !sawFirst {
                await prefix.publish(nil)
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                reader.cancel()
            }
        }
        guard let first = await prefix.first() else {
            reader.cancel()
            finish.finish()
            throw CodexErr.stream("stream closed before response.completed")
        }
        if case .failure(let error) = first, responsesEndpointMissing(error) {
            reader.cancel()
            finish.finish()
            throw error
        }
        return gateToolEvents(CodexCore.ResponseStream(events: bridged), decide: decide)
    }

    /// Drops function-call events whose id is not allowed. Other provider
    /// events, including `completed` usage, stay in order.
    static func replay(
        _ events: [CodexResult<ResponseEvent>],
        allowing callIDs: Set<String>?
    ) -> CodexCore.ResponseStream {
        makeResponseStream(filteredEvents(events, allowing: callIDs))
    }

    static func filteredEvents(
        _ events: [CodexResult<ResponseEvent>],
        allowing callIDs: Set<String>?
    ) -> [CodexResult<ResponseEvent>] {
        guard let callIDs else { return events }
        return events.filter { event in
            guard case .success(let value) = event else { return true }
            switch value {
            case .outputItemDone(let item), .outputItemAdded(let item):
                if let callID = functionCallID(item) {
                    return callIDs.contains(callID)
                }
                return true
            case .toolCallInputDelta(_, let callID, _):
                if let callID {
                    return callIDs.contains(callID)
                }
                return true
            default:
                return true
            }
        }
    }

    private static func functionCallID(_ item: ResponseItem) -> String? {
        if case .functionCall(_, _, _, _, _, let callID, _) = item {
            return callID
        }
        return nil
    }

    private static func gateToolEvents(
        _ stream: CodexCore.ResponseStream,
        decide: @escaping (ModelTurn) async -> ResponsesToolGate
    ) -> CodexCore.ResponseStream {
        let (events, continuation) = AsyncStream<CodexResult<ResponseEvent>>.makeStream()
        let task = Task {
            var builder = ResponseAccumulator()
            var held: [CodexResult<ResponseEvent>] = []
            var holding = false
            for await event in stream.events {
                if Task.isCancelled { break }
                switch event {
                case .failure:
                    continuation.yield(event)
                    continuation.finish()
                    return
                case .success(let value):
                    builder.observe(value)
                    if isToolEvent(value) {
                        holding = true
                        held.append(event)
                        continue
                    }
                    if case .completed = value {
                        await emitGatedCompletion(
                            value,
                            turn: builder.turn,
                            held: held,
                            decide: decide,
                            continuation: continuation
                        )
                        return
                    }
                    if holding {
                        held.append(event)
                    } else {
                        continuation.yield(event)
                    }
                }
            }
            if !Task.isCancelled {
                continuation.yield(.failure(CodexErr.stream("stream closed before response.completed")))
                continuation.finish()
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                task.cancel()
            }
        }
        return CodexCore.ResponseStream(events: events)
    }

    private static func emitGatedCompletion(
        _ completed: ResponseEvent,
        turn: ModelTurn,
        held: [CodexResult<ResponseEvent>],
        decide: (ModelTurn) async -> ResponsesToolGate,
        continuation: AsyncStream<CodexResult<ResponseEvent>>.Continuation
    ) async {
        if turn.toolCalls.isEmpty {
            for event in held {
                continuation.yield(event)
            }
            continuation.yield(.success(completed))
            continuation.finish()
            return
        }
        let gate = await decide(turn)
        let allowing: Set<String>
        let endTurn: Bool?
        switch gate {
        case .admit(let callIDs):
            allowing = callIDs
            endTurn = nil
        case .followUpWithoutTools:
            allowing = []
            endTurn = false
        case .finishWithoutTools:
            allowing = []
            endTurn = true
        }
        for event in filteredEvents(held, allowing: allowing) {
            continuation.yield(event)
        }
        continuation.yield(.success(replacingEndTurn(completed, with: endTurn)))
        continuation.finish()
    }

    private static func replacingEndTurn(_ event: ResponseEvent, with endTurn: Bool?) -> ResponseEvent {
        guard let endTurn,
              case .completed(let responseId, let tokenUsage, let usageMetadata, _) = event else {
            return event
        }
        return .completed(
            responseId: responseId,
            tokenUsage: tokenUsage,
            usageMetadata: usageMetadata,
            endTurn: endTurn
        )
    }

    private static func isToolEvent(_ event: ResponseEvent) -> Bool {
        switch event {
        case .outputItemDone(let item), .outputItemAdded(let item):
            return functionCallID(item) != nil
        case .toolCallInputDelta:
            return true
        default:
            return false
        }
    }

    private struct ResponseAccumulator {
        var deltas = ""
        var messageText = ""
        var calls: [ToolCallProposal] = []

        mutating func observe(_ event: ResponseEvent) {
            switch event {
            case .outputTextDelta(let delta):
                deltas += delta
            case .outputItemDone(let item):
                switch item {
                case .message(_, _, let content, _, _):
                    let text = ExecuteHarnessAttach.plainText(from: content)
                    if !text.isEmpty {
                        messageText = messageText.isEmpty ? text : messageText + "\n" + text
                    }
                case .functionCall(_, let name, _, let arguments, _, let callId, _):
                    calls.append(
                        ToolCallProposal(id: callId, name: name, argumentsJSON: arguments)
                    )
                default:
                    break
                }
            default:
                break
            }
        }

        var turn: ModelTurn {
            let text = messageText.isEmpty ? deltas : messageText
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ModelTurn(content: trimmed.isEmpty ? nil : trimmed, toolCalls: calls)
        }
    }

    static func responsesEndpointMissing(_ error: CodexErr) -> Bool {
        guard case .unexpectedStatus(let status) = error.details else { return false }
        return status.status == 404
    }

    static func modelTurn(from stream: CodexCore.ResponseStream) async throws -> ModelTurn {
        try await collectResponses(from: stream).turn
    }

    private static func responsesTool(_ tool: ToolDefinition) -> CodexProtocol.JSONValue {
        .object([
            "type": .string("function"),
            "name": .string(tool.name),
            "description": .string(tool.description),
            "parameters": protocolJSON(tool.parameters),
        ])
    }

    private static func protocolJSON(_ value: Sage.JSONValue) -> CodexProtocol.JSONValue {
        switch value {
        case .null:
            return .null
        case .bool(let flag):
            return .bool(flag)
        case .number(let number):
            if number.rounded() == number,
               number >= Double(Int64.min),
               number <= Double(Int64.max) {
                return .int(Int64(number))
            }
            return .double(number)
        case .string(let text):
            return .string(text)
        case .array(let items):
            return .array(items.map(protocolJSON))
        case .object(let fields):
            return .object(fields.mapValues(protocolJSON))
        }
    }

    private static func plainText(from content: [ContentItem]) -> String {
        content.compactMap { item -> String? in
            switch item {
            case .inputText(let text), .outputText(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : text
            case .inputImage, .inputAudio:
                return nil
            }
        }.joined(separator: "\n")
    }

    private static func contentItem(from input: UserInput) -> ContentItem {
        switch input {
        case .text(let text, _):
            return .inputText(text: text)
        case .localImage(let path, _):
            return .inputText(text: path)
        default:
            return .inputText(text: String(describing: input))
        }
    }
}

/// First event of a Responses stream, published from the reader task.
private actor ResponsePrefix {
    private var value: CodexResult<ResponseEvent>?
    private var ended = false
    private var waiters: [CheckedContinuation<CodexResult<ResponseEvent>?, Never>] = []

    func publish(_ event: CodexResult<ResponseEvent>?) {
        if let event, value == nil {
            value = event
        }
        if event == nil {
            ended = true
        }
        guard value != nil || ended else { return }
        let pending = waiters
        waiters.removeAll()
        let result = value
        for waiter in pending {
            waiter.resume(returning: result)
        }
    }

    func first() async -> CodexResult<ResponseEvent>? {
        if let value { return value }
        if ended { return nil }
        return await withCheckedContinuation { continuation in
            if let value {
                continuation.resume(returning: value)
                return
            }
            if ended {
                continuation.resume(returning: nil)
                return
            }
            waiters.append(continuation)
        }
    }
}

/// `AsyncStream.Continuation.finish` is single-shot.
private final class OnceFinish: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<CodexResult<ResponseEvent>>.Continuation?
    private var finished = false

    init(_ continuation: AsyncStream<CodexResult<ResponseEvent>>.Continuation) {
        self.continuation = continuation
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation?.finish()
        continuation = nil
    }
}
