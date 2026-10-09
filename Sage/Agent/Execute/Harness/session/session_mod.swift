//
//  session_mod.swift
//  CodexCore
//
//  Port of codex-rs/core/src/session/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Live thread admission: `ThreadSession` is the `SessionIo` submission
//  loop `ThreadManager` starts for every thread. Start, steer, and
//  drain decisions are `turn_input.swift`. A started regular turn runs
//  the `RegularTask` sample loop when a `TurnSampler` is attached
//  (`ModelClientTurnSampler` streams through `ModelClient`). Function
//  calls continue the turn through `TurnToolRunner`. Compact, hooks, and
//  the app tool runtime stay on the app-target `Session`.
//

import CodexAsyncUtils
import CodexProtocol
import Foundation
import os

private let submissionChannelCapacity = 512

enum LiveTurnKind: Equatable, Sendable {
    case regular
    case review
    case compact
}

private struct ActiveLiveTurn: Sendable {
    var id: String
    var kind: LiveTurnKind
    var finalOutputJsonSchema: JSONValue?
}

private final class SubmissionReply: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<TurnInputSubmission, CodexErr>?
    private var waiter: CheckedContinuation<Result<TurnInputSubmission, CodexErr>, Never>?

    func succeed(_ value: TurnInputSubmission) {
        finish(.success(value))
    }

    func fail(_ error: CodexErr) {
        finish(.failure(error))
    }

    func wait() async throws -> TurnInputSubmission {
        let result: Result<TurnInputSubmission, CodexErr> = await withCheckedContinuation { continuation in
            lock.lock()
            if let value {
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            waiter = continuation
            lock.unlock()
        }
        return try result.get()
    }

    private func finish(_ result: Result<TurnInputSubmission, CodexErr>) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: result)
            return
        }
        if value == nil {
            value = result
        }
        lock.unlock()
    }
}

private final class Ack: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func signal() {
        lock.lock()
        fired = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}

private final class SamplingResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var finished = false
    private var waiter: CheckedContinuation<String?, Never>?

    func succeed(_ value: String?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        self.value = value
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(returning: value)
    }

    func wait() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            lock.lock()
            if finished {
                let value = self.value
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }
}

/// One function call requested by a regular-turn sample.
public struct TurnFunctionCall: Equatable, Sendable {
    public var callId: String
    public var name: String
    public var namespace: String?
    public var arguments: String

    public init(callId: String, name: String, namespace: String? = nil, arguments: String) {
        self.callId = callId
        self.name = name
        self.namespace = namespace
        self.arguments = arguments
    }
}

/// Assistant text plus any function calls from one model sample.
public struct TurnSample: Equatable, Sendable {
    public var assistantText: String?
    public var functionCalls: [TurnFunctionCall]

    public init(assistantText: String? = nil, functionCalls: [TurnFunctionCall] = []) {
        self.assistantText = assistantText
        self.functionCalls = functionCalls
    }
}

/// One model sample for a regular turn. Rust calls this from `RegularTask::run` → `run_turn`.
/// `nil` means the sample was cancelled.
public protocol TurnSampler: Sendable {
    func sampleTurn(
        turnId: String,
        input: [TurnInput],
        cancellation: CancellationToken
    ) async throws -> TurnSample?
}

/// Runs function calls inside a regular turn and returns model-visible output text.
public protocol TurnToolRunner: Sendable {
    func runTool(
        turnId: String,
        call: TurnFunctionCall,
        cancellation: CancellationToken
    ) async throws -> String
}

/// Streams one regular-turn sample through `ModelClient`.
public struct ModelClientTurnSampler: TurnSampler {
    public let client: ModelClient
    public let model: String

    public init(client: ModelClient, model: String) {
        self.client = client
        self.model = model
    }

    public func sampleTurn(
        turnId: String,
        input: [TurnInput],
        cancellation: CancellationToken
    ) async throws -> TurnSample? {
        if cancellation.isCancelled { return nil }
        let session = client.newSession()
        let stream = try await session.stream(
            prompt: Prompt(input: responseItems(from: input)),
            modelInfo: minimalModelInfo(slug: model),
            responsesMetadata: CodexResponsesMetadata(
                installationId: "sage",
                sessionId: client.threadId.description,
                threadId: client.threadId.description,
                windowId: turnId
            )
        )
        var text = ""
        var calls: [TurnFunctionCall] = []
        for await event in stream.events {
            if cancellation.isCancelled {
                stream.consumerDropped.cancel()
                return nil
            }
            switch event {
            case .success(.outputTextDelta(let delta)):
                text += delta
            case .success(.outputItemDone(let item)):
                if let message = assistantMessageText(item) {
                    text = message
                }
                if let call = turnFunctionCall(item) {
                    calls.append(call)
                }
            case .failure(let error):
                stream.consumerDropped.cancel()
                throw error
            default:
                break
            }
        }
        return TurnSample(
            assistantText: text.isEmpty ? nil : text,
            functionCalls: calls
        )
    }
}

private enum LiveOp: Sendable {
    case interrupt(Ack)
    case shutdown
    case turnInput(TurnInputRequest, TurnInputMode, SubmissionReply)
    case interAgent(InterAgentCommunication, TurnStartOptions)
}

private struct LiveSubmission: Sendable {
    var id: String
    var op: LiveOp
}

private actor SubmissionInbox {
    private var items: [LiveSubmission] = []
    private var recvWaiters: [CheckedContinuation<LiveSubmission?, Never>] = []
    private var spaceWaiters: [CheckedContinuation<Void, Never>] = []
    private var closed = false

    func send(_ item: LiveSubmission) async -> Bool {
        if closed { return false }
        if !recvWaiters.isEmpty {
            recvWaiters.removeFirst().resume(returning: item)
            return true
        }
        while items.count >= submissionChannelCapacity && !closed {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                spaceWaiters.append(continuation)
            }
        }
        if closed { return false }
        if !recvWaiters.isEmpty {
            recvWaiters.removeFirst().resume(returning: item)
            return true
        }
        items.append(item)
        return true
    }

    func recv() async -> LiveSubmission? {
        if !items.isEmpty {
            let item = items.removeFirst()
            if !spaceWaiters.isEmpty {
                spaceWaiters.removeFirst().resume()
            }
            return item
        }
        if closed { return nil }
        return await withCheckedContinuation { continuation in
            recvWaiters.append(continuation)
        }
    }

    func closeAndDrain() -> [LiveSubmission] {
        closed = true
        let pending = items
        items = []
        let receivers = recvWaiters
        recvWaiters = []
        for waiter in receivers {
            waiter.resume(returning: nil)
        }
        let spaces = spaceWaiters
        spaceWaiters = []
        for waiter in spaces {
            waiter.resume()
        }
        return pending
    }
}

/// Submission loop for one live thread. Rust names this `Session` plus `SessionIo`.
public final class ThreadSession: @unchecked Sendable {
    public let threadId: ThreadId
    public let sessionSource: SessionSource

    private let inbox = SubmissionInbox()
    private let onEvent: @Sendable (Event) -> Void
    private let sampler: (any TurnSampler)?
    private let toolRunner: (any TurnToolRunner)?
    private let state = OSAllocatedUnfairLock(initialState: LoopState())
    private var loop: Task<Void, Never>?

    private struct LoopState: Sendable {
        var mode: ModeKind = .default
        var admitsTurnStart = true
        var closed = false
        var active: ActiveLiveTurn?
        var lastStartedTurnId: String?
        var pending: [TurnInput] = []
        var additionalContext: [String: AdditionalContextEntry] = [:]
        var mailbox: [(InterAgentCommunication, TurnStartOptions)] = []
        var samplingToken: CancellationToken?
        var samplingResult: SamplingResultBox?
        var interruptEpoch = 0
    }

    public static func open(
        threadId: ThreadId,
        sessionSource: SessionSource,
        sampler: (any TurnSampler)? = nil,
        toolRunner: (any TurnToolRunner)? = nil,
        onEvent: @escaping @Sendable (Event) -> Void = { _ in }
    ) -> ThreadSession {
        let session = ThreadSession(
            threadId: threadId,
            sessionSource: sessionSource,
            sampler: sampler,
            toolRunner: toolRunner,
            onEvent: onEvent
        )
        session.loop = Task { await session.run() }
        return session
    }

    private init(
        threadId: ThreadId,
        sessionSource: SessionSource,
        sampler: (any TurnSampler)?,
        toolRunner: (any TurnToolRunner)?,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.threadId = threadId
        self.sessionSource = sessionSource
        self.sampler = sampler
        self.toolRunner = toolRunner
        self.onEvent = onEvent
    }

    public func activeTurnId() -> String? {
        state.withLock { $0.active?.id }
    }

    public func pendingInputs() -> [TurnInput] {
        state.withLock { $0.pending }
    }

    public func collaborationMode() -> ModeKind {
        state.withLock { $0.mode }
    }

    public func setCollaborationMode(_ mode: ModeKind) {
        state.withLock { $0.mode = mode }
    }

    public func setAdmitsTurnStart(_ admits: Bool) {
        state.withLock { $0.admitsTurnStart = admits }
    }

    public func submitTurnInput(
        _ request: TurnInputRequest,
        mode: TurnInputMode
    ) async throws -> TurnInputSubmission {
        let reply = SubmissionReply()
        let submission = LiveSubmission(
            id: newSubmissionId(),
            op: .turnInput(request, mode, reply)
        )
        guard await inbox.send(submission) else {
            throw CodexErr.internalAgentDied
        }
        return try await reply.wait()
    }

    public func submitInterAgent(
        _ communication: InterAgentCommunication,
        startOptions: TurnStartOptions = TurnStartOptions()
    ) async throws {
        let submission = LiveSubmission(
            id: newSubmissionId(),
            op: .interAgent(communication, startOptions)
        )
        guard await inbox.send(submission) else {
            throw CodexErr.internalAgentDied
        }
    }

    public func interrupt() async {
        let ack = Ack()
        let submission = LiveSubmission(id: newSubmissionId(), op: .interrupt(ack))
        guard await inbox.send(submission) else {
            ack.signal()
            return
        }
        await ack.wait()
    }

    /// Last assistant text from the in-flight regular-turn sample, or nil when it was interrupted.
    public func waitForSamplingResult() async -> String? {
        let box = state.withLock { $0.samplingResult }
        guard let box else { return nil }
        return await box.wait()
    }

    public func shutdown() async {
        let submission = LiveSubmission(id: newSubmissionId(), op: .shutdown)
        _ = await inbox.send(submission)
        await loop?.value
    }

    private func run() async {
        var shutdownReceived = false
        while let submission = await inbox.recv() {
            if await dispatch(submission) {
                shutdownReceived = true
                break
            }
        }
        let leftovers = await inbox.closeAndDrain()
        for leftover in leftovers {
            fail(leftover, CodexErr.internalAgentDied)
        }
        if !shutdownReceived {
            finishShutdown(submissionId: "")
        }
    }

    private func dispatch(_ submission: LiveSubmission) async -> Bool {
        switch submission.op {
        case .interrupt(let ack):
            let token = state.withLock { loop -> CancellationToken? in
                loop.active = nil
                loop.interruptEpoch += 1
                let token = loop.samplingToken
                loop.samplingToken = nil
                return token
            }
            token?.cancel()
            ack.signal()
            return false
        case .shutdown:
            finishShutdown(submissionId: submission.id)
            return true
        case .turnInput(let request, let mode, let reply):
            do {
                let result = try routeTurnInput(request, mode: mode, submissionId: submission.id)
                reply.succeed(result)
            } catch let error as CodexErr {
                reply.fail(error)
            } catch {
                reply.fail(CodexErr.fatal(String(describing: error)))
            }
            return false
        case .interAgent(let communication, let startOptions):
            acceptInterAgent(communication, startOptions: startOptions, submissionId: submission.id)
            return false
        }
    }

    private func routeTurnInput(
        _ request: TurnInputRequest,
        mode: TurnInputMode,
        submissionId: String
    ) throws -> TurnInputSubmission {
        switch mode {
        case .startOrSteer:
            return try startOrSteer(request, submissionId: submissionId)
        case .startIfIdle:
            let kind = turnStartKind(for: request.input, idleDefault: .automatic)
            return try startIfIdle(
                request,
                submissionId: submissionId,
                kind: kind,
                expectedPreviousTurnId: nil
            )
        case .continueIfIdle(let expectedPreviousTurnId):
            guard case .responseItem = request.input else {
                throw CodexErr.invalidRequest("continuation requires internal response input")
            }
            return try startIfIdle(
                request,
                submissionId: submissionId,
                kind: .recovery,
                expectedPreviousTurnId: expectedPreviousTurnId
            )
        case .steer(let expectedTurnId):
            return try steer(request, expectedTurnId: expectedTurnId, submissionId: submissionId)
        }
    }

    private func startOrSteer(
        _ request: TurnInputRequest,
        submissionId: String
    ) throws -> TurnInputSubmission {
        try validateStartOrSteerInput(request.input)
        if let rejection = steerRejection(request, expectedTurnId: nil) {
            if rejection == .noActiveTurn {
                if rejectedForDraining(request, kind: .user, route: .startOrSteer) {
                    return .notSubmitted(reason: .serverDraining)
                }
                return try startTurn(
                    request,
                    submissionId: submissionId,
                    kind: .user,
                    route: .startOrSteer
                )
            }
            return .notSubmitted(reason: rejection)
        }
        appendPending(acceptedTurnInput(request, kind: .user, route: .startOrSteer))
        applyAcceptedThreadSettings(request)
        let turnId = state.withLock { $0.active?.id ?? submissionId }
        return .steered(turnId: turnId)
    }

    private func startIfIdle(
        _ request: TurnInputRequest,
        submissionId: String,
        kind: TurnStartKind,
        expectedPreviousTurnId: String?
    ) throws -> TurnInputSubmission {
        let blocked = state.withLock { loop -> NotSubmittedReason? in
            if loop.mailbox.contains(where: { $0.0.triggerTurn }) {
                return .pendingTriggerTurn
            }
            if kind == .automatic && loop.mode == .plan {
                return .planMode
            }
            return nil
        }
        if let blocked {
            return .notSubmitted(reason: blocked)
        }
        if rejectedForDraining(request, kind: kind, route: .startIfIdle) {
            return .notSubmitted(reason: .serverDraining)
        }
        let idleBlock = state.withLock { loop -> NotSubmittedReason? in
            if loop.active != nil {
                return .notIdle
            }
            if let expectedPreviousTurnId, loop.lastStartedTurnId != expectedPreviousTurnId {
                return .superseded
            }
            return nil
        }
        if let idleBlock {
            return .notSubmitted(reason: idleBlock)
        }
        let proposed = request.threadSettings.mode ?? state.withLock { $0.mode }
        if kind == .automatic && !kind.permitsMode(proposed) {
            return .notSubmitted(reason: .planMode)
        }
        return try startTurn(
            request,
            submissionId: submissionId,
            kind: kind,
            route: .startIfIdle
        )
    }

    private func steer(
        _ request: TurnInputRequest,
        expectedTurnId: String,
        submissionId: String
    ) throws -> TurnInputSubmission {
        try validateSteerOnlyInput(request.input)
        if let rejection = steerRejection(request, expectedTurnId: expectedTurnId) {
            return .notSubmitted(reason: rejection)
        }
        _ = submissionId
        appendPending(acceptedTurnInput(request, kind: .user, route: .startOrSteer))
        applyAcceptedThreadSettings(request)
        let turnId = state.withLock { $0.active?.id ?? expectedTurnId }
        return .steered(turnId: turnId)
    }

    private func startTurn(
        _ request: TurnInputRequest,
        submissionId: String,
        kind: TurnStartKind,
        route: TurnAdmissionRoute
    ) throws -> TurnInputSubmission {
        let mode = state.withLock { $0.mode }
        let proposed = request.threadSettings.mode ?? mode
        if kind == .automatic && !kind.permitsMode(proposed) {
            return .notSubmitted(reason: .planMode)
        }
        let queued = acceptedTurnInput(request, kind: kind, route: route)
        state.withLock { loop in
            if let requested = request.threadSettings.mode {
                loop.mode = requested
            }
            loop.active = ActiveLiveTurn(
                id: submissionId,
                kind: .regular,
                finalOutputJsonSchema: request.start.finalOutputJsonSchema
            )
            loop.lastStartedTurnId = submissionId
            loop.pending.append(contentsOf: queued)
        }
        beginSampling(turnId: submissionId)
        return .started(turnId: submissionId)
    }

    private func acceptInterAgent(
        _ communication: InterAgentCommunication,
        startOptions: TurnStartOptions,
        submissionId: String
    ) {
        let shouldStart = state.withLock { loop -> Bool in
            loop.mailbox.append((communication, startOptions))
            guard communication.triggerTurn, loop.active == nil, loop.mode != .plan else {
                return false
            }
            loop.active = ActiveLiveTurn(id: submissionId, kind: .regular, finalOutputJsonSchema: nil)
            loop.lastStartedTurnId = submissionId
            loop.pending.append(.interAgentCommunication(communication))
            return true
        }
        if shouldStart {
            beginSampling(turnId: submissionId)
        }
    }

    private func steerRejection(
        _ request: TurnInputRequest,
        expectedTurnId: String?
    ) -> NotSubmittedReason? {
        state.withLock { loop in
            guard let active = loop.active else {
                return .noActiveTurn
            }
            if let expectedTurnId, expectedTurnId != active.id {
                return .expectedTurnMismatch(expected: expectedTurnId, actual: active.id)
            }
            switch active.kind {
            case .regular:
                break
            case .review:
                return .activeTurnNotSteerable(turnKind: .review)
            case .compact:
                return .activeTurnNotSteerable(turnKind: .compact)
            }
            if case .userInput(let content, _) = request.input, content.isEmpty {
                return .emptyInput
            }
            if let required = request.start.finalOutputJsonSchema,
               active.finalOutputJsonSchema != required
            {
                return .activeTurnOutputSchemaMismatch
            }
            return nil
        }
    }

    private func rejectedForDraining(
        _ request: TurnInputRequest,
        kind: TurnStartKind,
        route: TurnAdmissionRoute
    ) -> Bool {
        turnInputRejectedForDraining(
            admitsTurnStart: state.withLock { $0.admitsTurnStart },
            route: route,
            kind: kind,
            source: sessionSource,
            parentTurnId: request.start.parentTurnId
        )
    }

    private func acceptedTurnInput(
        _ request: TurnInputRequest,
        kind: TurnStartKind,
        route: TurnAdmissionRoute
    ) -> [TurnInput] {
        var items = state.withLock { loop in
            additionalContextItems(merging: request.additionalContext, into: &loop.additionalContext)
        }
        if shouldEnqueueSubmittedInput(request.input, kind: kind, route: route) {
            items.append(request.input)
        }
        return items
    }

    private func applyAcceptedThreadSettings(_ request: TurnInputRequest) {
        guard let mode = request.threadSettings.mode else { return }
        state.withLock { $0.mode = mode }
    }

    private func appendPending(_ items: [TurnInput]) {
        guard !items.isEmpty else { return }
        state.withLock { $0.pending.append(contentsOf: items) }
    }

    private func finishShutdown(submissionId: String) {
        let token = state.withLock { loop -> CancellationToken? in
            loop.active = nil
            loop.closed = true
            loop.admitsTurnStart = false
            let token = loop.samplingToken
            loop.samplingToken = nil
            return token
        }
        token?.cancel()
        onEvent(Event(id: submissionId, msg: .shutdownComplete))
    }

    private func beginSampling(turnId: String) {
        guard let sampler else { return }
        let token = CancellationToken()
        let result = SamplingResultBox()
        let previous = state.withLock { loop -> CancellationToken? in
            let previous = loop.samplingToken
            loop.samplingToken = token
            loop.samplingResult = result
            return previous
        }
        previous?.cancel()
        onEvent(Event(id: turnId, msg: .turnStarted(TurnStartedEvent(turnId: turnId))))
        Task {
            await self.runRegularTurn(
                turnId: turnId,
                sampler: sampler,
                toolRunner: toolRunner,
                cancellation: token,
                result: result
            )
        }
    }

    /// `RegularTask::run`: sample, then sample again while steered input is waiting.
    private func runRegularTurn(
        turnId: String,
        sampler: any TurnSampler,
        toolRunner: (any TurnToolRunner)?,
        cancellation: CancellationToken,
        result: SamplingResultBox
    ) async {
        var lastText: String?
        var sampledOnce = false
        while !cancellation.isCancelled && !isClosed {
            let batch = state.withLock { loop -> [TurnInput] in
                let batch = loop.pending
                loop.pending.removeAll()
                return batch
            }
            if sampledOnce && batch.isEmpty { break }
            sampledOnce = true
            if cancellation.isCancelled || isClosed { break }
            do {
                let sample = try await sampler.sampleTurn(
                    turnId: turnId,
                    input: batch,
                    cancellation: cancellation
                )
                if cancellation.isCancelled || isClosed { break }
                guard let sample else { break }
                if let text = sample.assistantText, !text.isEmpty {
                    lastText = text
                }
                if !sample.functionCalls.isEmpty {
                    let outputs = try await functionCallOutputs(
                        turnId: turnId,
                        calls: sample.functionCalls,
                        toolRunner: toolRunner,
                        cancellation: cancellation
                    )
                    if cancellation.isCancelled || isClosed { break }
                    if !outputs.isEmpty {
                        state.withLock { loop in
                            loop.pending.insert(contentsOf: outputs, at: 0)
                        }
                    }
                }
            } catch {
                if !isClosed {
                    onEvent(
                        Event(
                            id: turnId,
                            msg: .error(ErrorEvent(message: String(describing: error)))
                        )
                    )
                    clearActiveTurn(turnId)
                }
                result.succeed(nil)
                return
            }
        }
        if cancellation.isCancelled || isClosed {
            if !isClosed {
                onEvent(
                    Event(
                        id: turnId,
                        msg: .turnComplete(
                            TurnCompleteEvent(turnId: turnId, interrupted: true)
                        )
                    )
                )
            }
            result.succeed(nil)
            return
        }
        guard clearActiveTurn(turnId) else {
            result.succeed(nil)
            return
        }
        if let lastText, !lastText.isEmpty {
            onEvent(Event(id: turnId, msg: .agentMessage(AgentMessageEvent(message: lastText))))
        }
        onEvent(Event(id: turnId, msg: .turnComplete(TurnCompleteEvent(turnId: turnId))))
        result.succeed(lastText)
    }

    /// Tool errors stay model-visible. A missing runner is terminal: the turn cannot continue.
    private func functionCallOutputs(
        turnId: String,
        calls: [TurnFunctionCall],
        toolRunner: (any TurnToolRunner)?,
        cancellation: CancellationToken
    ) async throws -> [TurnInput] {
        guard let toolRunner else {
            throw CodexErr.unsupportedOperation(
                "regular turn requested tools without a TurnToolRunner"
            )
        }
        var outputs: [TurnInput] = []
        for call in calls {
            if cancellation.isCancelled || isClosed { break }
            let text: String
            do {
                text = try await toolRunner.runTool(
                    turnId: turnId,
                    call: call,
                    cancellation: cancellation
                )
            } catch {
                if cancellation.isCancelled || isClosed { break }
                text = String(describing: error)
            }
            if cancellation.isCancelled || isClosed { break }
            outputs.append(functionCallOutputInput(call, text: text))
        }
        return outputs
    }

    private var isClosed: Bool {
        state.withLock { $0.closed }
    }

    @discardableResult
    private func clearActiveTurn(_ turnId: String) -> Bool {
        state.withLock { loop in
            guard loop.active?.id == turnId else { return false }
            loop.active = nil
            loop.samplingToken = nil
            return true
        }
    }

    private func fail(_ submission: LiveSubmission, _ error: CodexErr) {
        switch submission.op {
        case .turnInput(_, _, let reply):
            reply.fail(error)
        case .interrupt(let ack):
            ack.signal()
        case .shutdown, .interAgent:
            break
        }
    }
}

private func newSubmissionId() -> String {
    UUID().uuidString.lowercased()
}

private func responseItems(from input: [TurnInput]) -> [ResponseItem] {
    input.compactMap { item in
        switch item {
        case .userInput(let content, _):
            let text = content.compactMap { piece -> String? in
                if case .text(let text, _) = piece { return text }
                return nil
            }.joined(separator: "\n")
            guard !text.isEmpty else { return nil }
            return .message(
                id: nil,
                role: "user",
                content: [.inputText(text: text)],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            )
        case .responseItem(let item):
            return item
        case .interAgentCommunication(let communication):
            return .message(
                id: nil,
                role: "user",
                content: [.inputText(text: communication.content)],
                phase: nil,
                internalChatMessageMetadataPassthrough: nil
            )
        }
    }
}

private func turnFunctionCall(_ item: ResponseItem) -> TurnFunctionCall? {
    guard case .functionCall(_, let name, let namespace, let arguments, _, let callId, _) = item else {
        return nil
    }
    return TurnFunctionCall(
        callId: callId,
        name: name,
        namespace: namespace,
        arguments: arguments
    )
}

private func functionCallOutputInput(_ call: TurnFunctionCall, text: String) -> TurnInput {
    .responseItem(
        .functionCallOutput(
            id: nil,
            callId: call.callId,
            name: call.name,
            namespace: call.namespace,
            output: .fromText(text),
            internalChatMessageMetadataPassthrough: nil
        )
    )
}

private func assistantMessageText(_ item: ResponseItem) -> String? {
    guard case .message(_, let role, let content, _, _) = item, role == "assistant" else {
        return nil
    }
    let text = content.compactMap { piece -> String? in
        switch piece {
        case .inputText(let text), .outputText(let text):
            return text
        default:
            return nil
        }
    }.joined()
    return text.isEmpty ? nil : text
}
