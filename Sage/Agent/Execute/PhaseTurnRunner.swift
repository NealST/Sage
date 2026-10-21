//
//  PhaseTurnRunner.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  Runs one sub-agent phase turn (review, plan) on harness primitives.
//  M3: with a task harness attached, the turn rides the task's persistent
//  Session — the same root thread as Execute, so plan, execute, review,
//  and rework share one history and one rollout — and the phase behavior
//  (role prompt, tool set, dispatch) is carried entirely by the
//  TurnContext's allowlist + service overrides, leaving the session-level
//  Execute slots untouched. Without a harness (tests, pre-harness paths)
//  the turn attaches a throwaway Session instead. The turn's final
//  assistant message is the phase output. Brief assembly and output
//  parsing stay in the phase agents — this runner carries no phase
//  semantics. Tool calls and results are committed to the task transcript
//  so the phase's inspection is user-visible; text deltas can be observed
//  for streaming UI.
//
//  Tools follow the Execute shape: the full registry set is registered
//  through `sageToolSpecs` (turn-level on a shared session) and the phase
//  allowlist narrows what the model sees (`assembleToolRouter`) and what
//  dispatch accepts (`registry.dispatch`), so a mutating call is refused
//  with the same "not available this turn" gate as every other harness
//  turn.
//

import SageAPI
import SageAsyncUtils
import SageCore
import SageProtocol
import Foundation

/// Harness configuration for one phase turn. `tools` is the full
/// registration set; `toolAllowlist` is the phase's read-only subset —
/// D2's two narrow sets, enforced by both assembly and dispatch.
@MainActor
struct PhaseProfile {
    var modelRole: ModelRole
    var systemPrompt: String
    var tools: [ToolDefinition]
    var toolAllowlist: Set<String>

    /// Definitions the chat-completions fallback advertises: the
    /// allowlisted slice of the registration set.
    var allowlistedTools: [ToolDefinition] {
        tools.filter { toolAllowlist.contains($0.name) }
    }
}

@MainActor
final class PhaseTurnRunner {
    let state: AgentSessionState
    let modelGateway: AgentModelGateway
    let taskStore: AgentTaskStore

    /// Sole access to the persistent per-task harness Session (M3). When
    /// set (and not shut down) phase turns run on that session — the D1
    /// single-thread topology. `nil` keeps the throwaway-session form.
    var harnessProvider: (() -> TaskHarness?)?

    /// Executes one allowlisted tool call. An `ERROR:` prefix marks
    /// failure for the model; thrown errors are recorded the same way.
    var dispatchTool: ((ToolCallProposal) async throws -> String)?
    /// Test seam for the phase sample — receives the assembled prompt so
    /// tests can assert the visible tool set. Production samples through
    /// the gateway.
    var modelSampler: ((Prompt) async throws -> ModelTurn)?
    /// Live streaming observers (plan phase). Text arrives as provider
    /// deltas; a buffered sample delivers its whole message as one delta.
    /// Thinking arrives as deltas too — the observer accumulates. Review
    /// leaves both nil: its text is deliberately not streamed (the draft
    /// was already flushed).
    var onTextDelta: (@MainActor (String) -> Void)?
    var onThinkingDelta: (@MainActor (String) -> Void)?
    /// Start of a sampling round — a tool-follow-up round replaces the
    /// previous round's text on screen, so streaming observers reset
    /// per-message state here (Execute's `collectStream` has the same
    /// per-round boundary).
    var onSampleStart: (@MainActor () -> Void)?

    private var responsesLease: ExecuteHarnessAttach.ResponsesClientLease?
    private var responsesTransportUnavailable = false

    init(state: AgentSessionState, modelGateway: AgentModelGateway, taskStore: AgentTaskStore) {
        self.state = state
        self.modelGateway = modelGateway
        self.taskStore = taskStore
    }

    /// One phase turn. `userText` is the phase prompt (review brief /
    /// plan ask). Returns the turn's final assistant message.
    func runTurn(profile: PhaseProfile, userText: String) async throws -> String {
        try Task.checkCancellation()
        if let harness = harnessProvider?(), !harness.isShutDown {
            return try await runTurnOnTaskHarness(
                harness,
                profile: profile,
                userText: userText
            )
        }
        return try await runTurnOnEphemeralSession(profile: profile, userText: userText)
    }

    /// M3: the phase turn on the task's persistent Session. Everything
    /// phase-specific rides the TurnContext — `toolAllowlist` narrows
    /// assembly and dispatch, `serviceOverrides` lease the phase prompt,
    /// sampler, tool dispatch, and registration set for this turn only —
    /// so the session's Execute wiring (prepareSamplingPrompt, session
    /// sampler, Execute dispatch) stays exactly as the next execute turn
    /// expects it. The phase's Responses client comes from the harness
    /// lease pool, so phase roles and Execute share wire identity.
    private func runTurnOnTaskHarness(
        _ harness: TaskHarness,
        profile: PhaseProfile,
        userText: String
    ) async throws -> String {
        let settings = modelGateway.settings.snapshot(for: profile.modelRole)
        let turnContext = ExecuteHarnessAttach.makeTurnContext(
            cwd: cwd,
            model: settings.model,
            allowsMutation: false
        )
        turnContext.threadId = harness.threadId
        turnContext.sessionId = SessionId(harness.threadId)
        turnContext.toolAllowlist = profile.toolAllowlist
        let token = CancellationToken()
        let session = harness.session
        // Minted once per turn, like Execute's prewarmed client session;
        // every sampling round of this turn streams through it.
        let phaseClientSession: ModelClientSession?
        if harness.responsesTransportUnavailable(settings) {
            phaseClientSession = nil
        } else {
            phaseClientSession = harness.leaseClient(settings)?.client.newSession()
        }
        turnContext.serviceOverrides = TurnServiceOverrides(
            baseInstructions: profile.systemPrompt,
            runSamplingStreamOverride: { [weak self] prompt in
                guard let self else {
                    throw SageErr.fatal("phase turn runner is gone")
                }
                return try await self.sampleTurn(
                    prompt: prompt,
                    session: session,
                    profile: profile,
                    settings: settings,
                    turnContext: turnContext,
                    token: token,
                    clientSession: phaseClientSession,
                    stepContext: nil,
                    responsesUnavailable: harness.responsesTransportUnavailable(settings),
                    markResponsesUnavailable: {
                        harness.markResponsesTransportUnavailable(settings)
                    }
                )
            },
            onSageToolCall: { [weak self] name, callId, arguments in
                await self?.dispatchSageTool(name: name, callId: callId, argumentsJSON: arguments)
            },
            sageToolSpecs: ExecuteHarnessAttach.sageToolSpecs(profile.tools)
        )
        return try await withTaskCancellationHandler {
            await session.spawnTask(
                RegularSessionTask(),
                turnContext: turnContext,
                input: [TurnInputBuilder.user([.text(text: userText, textElements: [])])],
                cancellationToken: token
            )
            if token.isCancelled || session.lastTurnAbortReason != nil {
                throw CancellationError()
            }
            if let error = session.lastTaskError {
                if let sageError = error as? SageErr,
                   ExecuteHarnessAttach.responsesEndpointMissing(sageError) {
                    harness.markResponsesTransportUnavailable(settings)
                }
                throw error
            }
            try Task.checkCancellation()
            return session.lastTaskAgentMessage ?? ""
        } onCancel: {
            token.cancel()
        }
    }

    /// The throwaway-session form (no task harness): history is the brief
    /// alone, and the phase prompt / tool set live on the session slots
    /// because nothing else ever touches that Session.
    private func runTurnOnEphemeralSession(profile: PhaseProfile, userText: String) async throws -> String {
        let settings = modelGateway.settings.snapshot(for: profile.modelRole)
        responsesLease = ExecuteHarnessAttach.leaseResponsesClient(
            existing: responsesLease,
            baseURL: settings.baseURL,
            apiKey: settings.apiKey
        )
        let session = ExecuteHarnessAttach.makeSession(
            history: [],
            threadId: ThreadId(),
            discardEvents: true
        )
        if !responsesTransportUnavailable {
            session.services.modelClient = responsesLease?.client
        }
        session.services.parallelAdmission = state.parallelAdmission
        session.services.sageToolSpecs = ExecuteHarnessAttach.sageToolSpecs(profile.tools)
        session.state.sessionConfiguration.baseInstructions = profile.systemPrompt
        session.services.onSageToolCall = { [weak self] name, callId, arguments in
            await self?.dispatchSageTool(name: name, callId: callId, argumentsJSON: arguments)
        }
        let turnContext = ExecuteHarnessAttach.makeTurnContext(
            cwd: cwd,
            model: settings.model,
            allowsMutation: false
        )
        turnContext.threadId = session.threadId
        turnContext.sessionId = SessionId(session.threadId)
        turnContext.toolAllowlist = profile.toolAllowlist
        let token = CancellationToken()
        session.runSamplingStreamOverride = { [weak self, weak session] prompt in
            guard let self, let session else {
                throw SageErr.fatal("phase turn runner is gone")
            }
            return try await self.sampleTurn(
                prompt: prompt,
                session: session,
                profile: profile,
                settings: settings,
                turnContext: turnContext,
                token: token,
                clientSession: session.samplingClientSession
                    ?? session.services.modelClient?.newSession(),
                stepContext: session.samplingStepContext,
                responsesUnavailable: self.responsesTransportUnavailable,
                markResponsesUnavailable: {
                    self.responsesTransportUnavailable = true
                    session.services.modelClient = nil
                }
            )
        }
        return try await withTaskCancellationHandler {
            await session.spawnTask(
                RegularSessionTask(),
                turnContext: turnContext,
                input: [TurnInputBuilder.user([.text(text: userText, textElements: [])])],
                cancellationToken: token
            )
            if token.isCancelled || session.lastTurnAbortReason != nil {
                throw CancellationError()
            }
            if let error = session.lastTaskError {
                if let sageError = error as? SageErr,
                   ExecuteHarnessAttach.responsesEndpointMissing(sageError) {
                    responsesTransportUnavailable = true
                }
                throw error
            }
            try Task.checkCancellation()
            return session.lastTaskAgentMessage ?? ""
        } onCancel: {
            token.cancel()
        }
    }

    private var cwd: String { state.projectCWD }

    /// Live Responses stream when the transport is available, buffered
    /// sampler for tests, chat-completions fallback otherwise. Unlike
    /// Execute there is no admission gate: phase tools are pre-authorized
    /// by the allowlist, so provider events pass straight to `runTurn`.
    /// `clientSession` / `stepContext` are resolved by the caller at
    /// sampling time — the ephemeral path reads the session slots the
    /// session-level override just set, the shared-session path carries
    /// its own phase-role client and no step context.
    private func sampleTurn(
        prompt: Prompt,
        session: Session,
        profile: PhaseProfile,
        settings: ModelSettingsSnapshot,
        turnContext: TurnContext,
        token: CancellationToken,
        clientSession: ModelClientSession?,
        stepContext: StepContext?,
        responsesUnavailable: Bool,
        markResponsesUnavailable: () -> Void
    ) async throws -> SageCore.ResponseStream {
        if token.isCancelled {
            throw SageErr(details: .turnAborted)
        }
        onSampleStart?()
        if let modelSampler {
            let turn = try await modelSampler(prompt)
            feedTextDeltas(from: turn)
            return ExecuteHarnessAttach.responseStream(from: turn)
        }
        if !responsesUnavailable, let clientSession {
            do {
                let metadata = stepContext.map { session.responsesMetadata($0, requestKind: .turn) }
                    ?? ExecuteHarnessAttach.responsesMetadata(session: session, turn: turnContext)
                let modelInfo: ModelInfo
                if let stepContext, !stepContext.turn.model.isEmpty {
                    modelInfo = stepContext.turn.modelInfoValue()
                } else {
                    modelInfo = minimalModelInfo(slug: settings.model)
                }
                let stream = try await clientSession.stream(
                    prompt: prompt,
                    modelInfo: modelInfo,
                    responsesMetadata: metadata
                )
                return teeSampleDeltas(stream)
            } catch let error as SageErr where ExecuteHarnessAttach.responsesEndpointMissing(error) {
                markResponsesUnavailable()
            }
        }
        let conversation = ExecuteHarnessAttach.agentEvents(from: prompt.input)
        let events = [AgentEvent(kind: .systemInstruction, content: profile.systemPrompt)] + conversation
        let turn = try await modelGateway.completeUnstreamedTurn(
            events: events,
            tools: profile.allowlistedTools,
            role: profile.modelRole
        )
        feedTextDeltas(from: turn)
        return ExecuteHarnessAttach.responseStream(from: turn)
    }

    /// Buffered samplers have no provider deltas — the sample's message is
    /// one text delta, so the streaming UI still plays it through the pump.
    private func feedTextDeltas(from turn: ModelTurn) {
        if let content = turn.content, !content.isEmpty {
            onTextDelta?(content)
        }
    }

    /// Tees provider text / reasoning deltas to the streaming observers
    /// while passing every event through to `runTurn`. The reader hops to
    /// the main actor so phase observers (StreamingTextPump publishers)
    /// stay on their isolation domain. Providers that only send
    /// `outputItemDone` without deltas are a Responses-protocol violation;
    /// every other path feeds through `feedTextDeltas`.
    private func teeSampleDeltas(_ stream: SageCore.ResponseStream) -> SageCore.ResponseStream {
        guard onTextDelta != nil || onThinkingDelta != nil else {
            return stream
        }
        let (events, continuation) = AsyncStream<SageResult<ResponseEvent>>.makeStream()
        let textSink = onTextDelta
        let thinkingSink = onThinkingDelta
        let reader = Task { @MainActor in
            for await event in stream.events {
                if Task.isCancelled { return }
                if case .success(let value) = event {
                    switch value {
                    case .outputTextDelta(let delta):
                        textSink?(delta)
                    case .reasoningSummaryDelta(let delta, summaryIndex: _):
                        thinkingSink?(delta)
                    case .reasoningContentDelta(let delta, contentIndex: _):
                        thinkingSink?(delta)
                    default:
                        break
                    }
                }
                continuation.yield(event)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            reader.cancel()
        }
        return SageCore.ResponseStream(events: events)
    }

    /// The seam `runTurn`'s tool dispatch calls. Executes through
    /// `dispatchTool` and commits the call + result to the transcript,
    /// mirroring Execute's `recordHarnessToolResult` event mapping minus
    /// the pending-plan bookkeeping (phases have no plan steps).
    private func dispatchSageTool(name: String, callId: String, argumentsJSON: String) async -> String? {
        let call = ToolCallRecord(id: callId, name: name, argumentsJSON: argumentsJSON)
        _ = await taskStore.commit(
            appendEvents: [AgentEvent(kind: .assistantResponse, content: "", toolCalls: [call])],
            deleteEventIDs: []
        ) { _ in }
        let output: String
        do {
            if let dispatchTool {
                output = try await dispatchTool(ToolCallProposal(id: callId, name: name, argumentsJSON: argumentsJSON))
            } else {
                output = "ERROR: Phase tool invoke is not attached"
            }
        } catch {
            output = "ERROR: \(error.localizedDescription)"
        }
        _ = await taskStore.commit(
            appendEvents: [AgentEvent(kind: .toolResult, content: output, toolCallID: callId)],
            deleteEventIDs: []
        ) { _ in }
        return output
    }
}
