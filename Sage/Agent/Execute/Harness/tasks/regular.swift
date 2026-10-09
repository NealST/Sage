//
//  regular.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/regular.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `RegularSessionTask` is rust `RegularTask`: emit start, consume
//  prewarm, then `runTurn` until the input queue is idle or a terminal
//  error is set. Sage `RegularTask` attaches a harness Session from
//  AgentSessionState on `start()`. When `useHarnessRunTurn`, sampling
//  and tool dispatch go through `runTurn`. Follow-up samples stream
//  the prompt `buildPrompt` assembled, through the ModelClientSession
//  that turn already opened. Sage's system text and tool schemas are
//  written onto that prompt first. Provider text and usage reach
//  `runTurn` as they arrive. Function calls stay out until HUD admission.
//  A host without `/responses` falls back to chat completions.
//  HUD approval is admitted before dispatch so the card never waits
//  inside `runTurn`. Attach binds the allowlist ApprovalStore, the
//  session ParallelAdmission, and HookRuntime project/skills so
//  `registry.dispatch` owns Pre/PostToolUse.
//  Resume replays the pending calls through that same dispatch.
//

import CodexAsyncUtils
import CodexCore
import CodexProtocol
import CodexThreadStore
import Foundation

/// Codex `RegularTask`.
final class RegularSessionTask: SessionTask, @unchecked Sendable {
    var kind: TaskKind { .regular }
    /// Test seam: runs after each `runTurn` so pending input can be queued
    /// for the rust outer loop.
    var afterRunTurn: (() -> Void)?

    init() {}

    func run(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async throws -> String? {
        if session.activeTurn == nil {
            session.activeTurn = ActiveTurn(
                task: RunningTask(kind: .regular, turnContext: context),
                turnState: TurnState()
            )
        } else if session.activeTurn?.task == nil {
            session.activeTurn?.task = RunningTask(kind: .regular, turnContext: context)
        }
        session.emitTurnStarted(context)

        let prewarmedClientSession = await prepareRunTurn(
            session: session,
            context: context,
            input: input,
            cancellationToken: cancellationToken
        )
        switch prewarmedClientSession {
        case .cancelled:
            return nil
        case .unavailable, .ready:
            break
        }

        var nextInput = input
        var prewarmed = prewarmedClientSession.readySession
        var mcpStartupRequirements = McpStartupRequirements()
        while true {
            let lastAgentMessage = try await runTurn(
                sess: session,
                turnContext: context,
                input: &nextInput,
                mcpStartupRequirements: &mcpStartupRequirements,
                prewarmedClientSession: prewarmed,
                cancellationToken: cancellationToken.childToken()
            )
            prewarmed = nil
            afterRunTurn?()
            if cancellationToken.isCancelled {
                throw CodexErr(details: .turnAborted)
            }
            if context.terminalError != nil {
                return lastAgentMessage
            }
            if !session.inputQueue.hasPendingInput(session.activeTurn) {
                return lastAgentMessage
            }
            nextInput = []
        }
    }

    private func prepareRunTurn(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async -> SessionStartupPrewarmResolution {
        await session.emitTurnStartLifecycle(
            context,
            tokenUsageAtTurnStart: nil,
            phase: .regularTaskStart
        )
        session.requestMcpRuntimeReprojection()
        if cancellationToken.isCancelled {
            _ = await runHooksAndRecordInputs(
                sess: session,
                turnContext: context,
                modelInfo: context.captureCurrentModelInfo(),
                input: input,
                persistContext: .standard
            )
            return .cancelled
        }
        session.setServerReasoningIncluded(false)
        let resolution = await session.consumeStartupPrewarm(
            cancellationToken: cancellationToken
        )
        if case .cancelled = resolution {
            _ = await runHooksAndRecordInputs(
                sess: session,
                turnContext: context,
                modelInfo: context.captureCurrentModelInfo(),
                input: input,
                persistContext: .standard
            )
        }
        return resolution
    }
}

private extension SessionStartupPrewarmResolution {
    var readySession: ModelClientSession? {
        if case .ready(let session) = self { return session }
        return nil
    }
}

/// Execute entry on `TurnCoordinator`.
@MainActor
final class RegularTask: ExecuteTurnLoop {
    let state: AgentSessionState
    let planProgress: PlanProgress
    let taskStore: AgentTaskStore
    let modelGateway: AgentModelGateway
    let streaming: StreamingTextPump

    /// One in-flight tool batch. Returns when the batch pauses, fails, or finishes.
    /// Sampling the next model step is `session/turn.swift`, not this closure.
    var runToolBatch: ((Bool) async -> ToolBatchExecutor.WaveOutcome)?
    var onCandidateReply: ((String) async -> Void)?
    var handleStop: ((AgentPlan?) async -> Void)?
    /// Connect enabled MCP servers that are not already running. Codex starts
    /// them inside `run_turn`, before the model is asked.
    var ensureMCPConnected: (() async -> Void)?
    /// Replace live clients. A published reconnect uses this instead of ensure.
    var reconnectMCP: (() async -> Void)?
    /// Stop clients for servers a publish disabled or removed.
    var disconnectMCP: (([String]) async -> Void)?
    /// Model-visible MCP catalog. Server name is the CapabilityStore server id.
    var mcpVisibleCatalog: (() -> [McpVisibleTool])?
    /// Test seam for `ModelClientSession::stream`. Production uses `modelGateway`.
    var modelSampler: ((Bool) async throws -> ModelTurn)?
    /// Prepared rust Session. Live Execute uses `runTurn` when
    /// `useHarnessRunTurn` is set (from ModelSettings).
    var harnessSession: Session?
    var harnessTurnContext: TurnContext?
    var harnessInput: [SessionTurnInput] = []
    var harnessCancellation: CancellationToken?
    /// Flip when tool dispatch is attached. Until then `start()` keeps `Turn.run`.
    var useHarnessRunTurn = false
    /// Conversations handed to the model, one entry per harness sample.
    var harnessSampleConversations: [[AgentEvent]] = []
    /// Live Sage tool invoke (ExecuteServices). Tests can stub this.
    var invokeHarnessTool: ((ToolCallProposal) async throws -> String)?
    /// Activated skills for registry Pre/PostToolUse (skill `hooks.json`).
    var hookActivatedSkills: (() -> [SkillRecord])?
    /// Approval / validation gate for a tool-bearing sample. Nil means the
    /// calls are ready for `runTurn` to dispatch.
    var admitHarnessBatch: (() async -> ToolBatchExecutor.AdmitOutcome)?
    /// Set when admission pauses or fails, so the turn does not publish a reply.
    private var harnessTurnSettled = false
    /// Pending calls to dispatch on the next `runTurn`, without sampling first.
    private var resumeToolTurn: ModelTurn?
    /// Host returned 404 for `/responses`; later samples stay on chat completions.
    private var responsesTransportUnavailable = false
    /// Responses client for this Execute thread. Reinstalled on each Session.
    private var responsesLease: ExecuteHarnessAttach.ResponsesClientLease?
    private var harnessIncludeTools = true

    private(set) var toolBatchCount = 0
    /// Codex `stop_hook_active`: a Stop hook continuation is not blocked again.
    private var stopHookActive = false
    /// SessionStart / UserPromptSubmit fire once per execute loop.
    private var sessionStartConsumed = false
    private var harnessRolloutPath: String?
    private var pendingAttachSessionStartSource: SessionStartSource?
    private var userPromptSubmitConsumed = false
    private var abortReason: String?

    init(
        state: AgentSessionState,
        planProgress: PlanProgress,
        taskStore: AgentTaskStore,
        modelGateway: AgentModelGateway,
        streaming: StreamingTextPump
    ) {
        self.state = state
        self.planProgress = planProgress
        self.taskStore = taskStore
        self.modelGateway = modelGateway
        self.streaming = streaming
    }

    func bind(
        runToolBatch: @escaping (Bool) async -> ToolBatchExecutor.WaveOutcome,
        onCandidateReply: @escaping (String) async -> Void,
        handleStop: @escaping (AgentPlan?) async -> Void,
        ensureMCPConnected: (() async -> Void)? = nil,
        reconnectMCP: (() async -> Void)? = nil,
        disconnectMCP: (([String]) async -> Void)? = nil,
        invokeHarnessTool: ((ToolCallProposal) async throws -> String)? = nil
    ) {
        self.runToolBatch = runToolBatch
        self.onCandidateReply = onCandidateReply
        self.handleStop = handleStop
        self.ensureMCPConnected = ensureMCPConnected
        self.reconnectMCP = reconnectMCP
        self.disconnectMCP = disconnectMCP
        self.invokeHarnessTool = invokeHarnessTool
    }

    func resetLoop() {
        toolBatchCount = 0
        stopHookActive = false
        sessionStartConsumed = false
        pendingAttachSessionStartSource = nil
        userPromptSubmitConsumed = false
        abortReason = nil
    }

    /// Execute keeps going until the model stops or the user stops. Explore still caps its own rounds.
    var canOfferMoreTools: Bool { true }

    func extendToolBatchLimit() {}

    /// Codex `RegularTask::run` → `run_turn` when `useHarnessRunTurn`.
    func start() async {
        state.workspaceChanges.beginIfNeeded(replaying: state.events)
        attachExecuteHarness()
        if useHarnessRunTurn {
            await runHarnessTurn()
            return
        }
        await Turn.run(self, includeTools: true)
    }

    func continueWithTools() async {
        if hasUnexecutedPendingBatch {
            toolBatchCount += 1
            await runPausedBatch(retryFailedSteps: false)
            return
        }
        attachExecuteHarness()
        if useHarnessRunTurn {
            await runHarnessTurn()
            return
        }
        await Turn.run(self, includeTools: true)
    }

    func attachExecuteHarness() {
        let cwd = projectRoot?.path ?? FileManager.default.currentDirectoryPath
        let settings = modelGateway.settings.snapshot(for: .execute)
        let snapshot = ExecuteHarnessAttach.snapshot(
            events: state.events,
            cwd: cwd,
            model: settings.model,
            allowsMutation: state.activeTask?.workPlan?.kind == .act
        )
        let previousURL = responsesLease?.baseURL
        responsesLease = ExecuteHarnessAttach.leaseResponsesClient(
            existing: responsesLease,
            baseURL: settings.baseURL,
            apiKey: settings.apiKey
        )
        if let previousURL, responsesLease?.baseURL != previousURL {
            responsesTransportUnavailable = false
        }
        let startSource = ExecuteHarnessAttach.attachStartSource(
            pending: state.takePendingSessionStartSource(),
            historyEmpty: snapshot.history.isEmpty
        )
        pendingAttachSessionStartSource = startSource
        let session = ExecuteHarnessAttach.makeSession(
            history: snapshot.history,
            threadId: responsesLease?.client.threadId ?? ThreadId(),
            startSource: startSource
        )
        session.services.modelClient = responsesTransportUnavailable ? nil : responsesLease?.client
        session.services.parallelAdmission = state.parallelAdmission
        session.services.approvalStore = state.sessionAllowlist.approvalStore
        session.services.hookProjectRoot = projectRoot
        session.services.hookActivatedSkills = hookActivatedSkills?() ?? []
        bindHarnessSampling(session)
        let turnContext = ExecuteHarnessAttach.makeTurnContext(
            cwd: snapshot.cwd,
            model: snapshot.model,
            allowsMutation: snapshot.allowsMutation
        )
        let previousRolloutPath = harnessSession?.persistedRolloutPath() ?? harnessRolloutPath
        if let previousRolloutPath {
            session.restoreVerifiedAnswers(
                fromRolloutPath: previousRolloutPath,
                truncationPolicy: TruncationPolicy(turnContext.modelInfoValue().truncationPolicy)
            )
            session.resumeRolloutPersistence(path: previousRolloutPath)
            harnessRolloutPath = previousRolloutPath
        } else {
            session.enableRolloutPersistence()
        }
        session.ensureSubmissionLoop()
        harnessSession = session
        harnessTurnContext = turnContext
        harnessInput = snapshot.input
    }

    private func bindHarnessSampling(_ session: Session) {
        guard useHarnessRunTurn else { return }
        installHarnessMcpBridge(on: session)
        session.services.sageToolNames = modelGateway.availableToolDefinitions().map(\.name)
        session.prepareSamplingPrompt = { [weak self] in
            guard let self else { return }
            let prefix = await self.modelGateway.samplingPrefix(includeTools: self.harnessIncludeTools)
            session.state.sessionConfiguration.baseInstructions = prefix.system
            session.services.sageResponsesTools = self.harnessIncludeTools
                ? ExecuteHarnessAttach.responsesTools(prefix.tools)
                : []
        }
        session.services.onSageToolCall = { [weak self] name, callId, arguments in
            await self?.dispatchSageTool(name: name, callId: callId, argumentsJSON: arguments)
        }
        guard session.runSamplingStreamOverride == nil, session.runSamplingOverride == nil else {
            return
        }
        session.runSamplingStreamOverride = { [weak self] prompt in
            guard let self else {
                throw CodexErr.fatal("execute harness sampler is gone")
            }
            if let resume = self.resumeToolTurn {
                self.resumeToolTurn = nil
                return await self.streamAdmittedTools(
                    resume,
                    recordAssistant: false,
                    countRound: false,
                    replacePlan: false
                )
            }
            switch try await self.openModelSample(prompt) {
            case .buffered(let sample):
                return await self.streamBuffered(sample)
            case .live(let stream):
                return stream
            }
        }
    }

    private enum OpenedSample {
        case buffered(LiveSample)
        case live(CodexCore.ResponseStream)
    }

    /// Sampler and chat completions have no provider event list. Screen the
    /// batch, then synthesize the stream `runTurn` dispatches.
    private func streamBuffered(_ sample: LiveSample) async -> CodexCore.ResponseStream {
        if sample.turn.toolCalls.isEmpty {
            return replay(sample)
        }
        switch await screenMutations(sample.turn) {
        case .refusedAll:
            toolBatchCount += 1
            return ExecuteHarnessAttach.responseStream(
                from: ModelTurn(content: nil, toolCalls: []),
                endTurn: false
            )
        case .proceed(let allowed):
            return await streamAdmittedTools(allowed, events: sample.events, recordAssistant: true)
        case .proceedAfterRefusal(let allowed):
            return await streamAdmittedTools(
                allowed,
                events: sample.events,
                recordAssistant: false
            )
        }
    }

    /// Persist the batch, admit it, then either hand the calls to `runTurn`
    /// or stop so a HUD card can take the turn.
    private func streamAdmittedTools(
        _ turn: ModelTurn,
        events: [CodexResult<ResponseEvent>]? = nil,
        recordAssistant: Bool,
        countRound: Bool = true,
        replacePlan: Bool = true
    ) async -> CodexCore.ResponseStream {
        switch await admittedGate(
            turn,
            recordAssistant: recordAssistant,
            countRound: countRound,
            replacePlan: replacePlan
        ) {
        case .admit:
            return replay(LiveSample(turn: turn, events: events))
        case .followUpWithoutTools:
            return ExecuteHarnessAttach.responseStream(
                from: ModelTurn(content: nil, toolCalls: []),
                endTurn: false
            )
        case .finishWithoutTools:
            return ExecuteHarnessAttach.responseStream(from: ModelTurn(content: nil, toolCalls: []))
        }
    }

    /// Persist and admit a batch. Live Responses uses the same decision to
    /// filter the provider stream instead of synthesizing one.
    private func admittedGate(
        _ turn: ModelTurn,
        recordAssistant: Bool,
        countRound: Bool = true,
        replacePlan: Bool = true
    ) async -> ExecuteHarnessAttach.ResponsesToolGate {
        if replacePlan {
            guard await persistIncomingToolBatch(turn, recordAssistant: recordAssistant) else {
                harnessTurnSettled = true
                return .finishWithoutTools
            }
        }
        if countRound {
            toolBatchCount += 1
        }
        switch await admitHarnessBatch?() ?? .ready {
        case .ready:
            return .admit(Set(turn.toolCalls.map(\.id)))
        case .halted:
            return .followUpWithoutTools
        case .paused, .persistFailed, .cancelled:
            harnessTurnSettled = true
            return .finishWithoutTools
        }
    }

    private func decideResponsesGate(_ turn: ModelTurn) async -> ExecuteHarnessAttach.ResponsesToolGate {
        switch await screenMutations(turn) {
        case .refusedAll:
            toolBatchCount += 1
            return .followUpWithoutTools
        case .proceed(let allowed):
            return await admittedGate(allowed, recordAssistant: true)
        case .proceedAfterRefusal(let allowed):
            return await admittedGate(allowed, recordAssistant: false)
        }
    }

    private struct LiveSample {
        var turn: ModelTurn
        var events: [CodexResult<ResponseEvent>]?
    }

    private func replay(_ sample: LiveSample) -> CodexCore.ResponseStream {
        if let events = sample.events {
            return ExecuteHarnessAttach.replay(
                events,
                allowing: Set(sample.turn.toolCalls.map(\.id))
            )
        }
        return ExecuteHarnessAttach.responseStream(from: sample.turn)
    }

    private func openModelSample(_ prompt: Prompt) async throws -> OpenedSample {
        let conversation = ExecuteHarnessAttach.agentEvents(from: prompt.input)
        harnessSampleConversations.append(conversation)
        if let modelSampler {
            return .buffered(LiveSample(turn: try await modelSampler(harnessIncludeTools), events: nil))
        }
        let snapshot = modelGateway.settings.snapshot(for: .execute)
        if !responsesTransportUnavailable,
           let session = harnessSession,
           let clientSession = session.samplingClientSession ?? session.services.modelClient?.newSession() {
            do {
                let step = session.samplingStepContext
                let metadata = step.map {
                    session.responsesMetadata($0, requestKind: .turn)
                } ?? ExecuteHarnessAttach.responsesMetadata(
                    session: session,
                    turn: harnessTurnContext
                )
                let upstream = try await clientSession.stream(
                    prompt: prompt,
                    modelInfo: responsesModelInfo(step: step, model: snapshot.model),
                    responsesMetadata: metadata
                )
                let live = try await ExecuteHarnessAttach.liveResponses(upstream) { [weak self] turn in
                    guard let self else { return .finishWithoutTools }
                    return await self.decideResponsesGate(turn)
                }
                return .live(live)
            } catch let error as CodexErr where ExecuteHarnessAttach.responsesEndpointMissing(error) {
                responsesTransportUnavailable = true
                session.services.modelClient = nil
            }
        }
        return .buffered(
            LiveSample(
                turn: try await modelGateway.streamComplete(
                    conversation: conversation,
                    includeTools: harnessIncludeTools
                ),
                events: nil
            )
        )
    }

    private func responsesModelInfo(step: StepContext?, model: String) -> ModelInfo {
        if let step, !step.turn.model.isEmpty {
            return step.turn.modelInfoValue()
        }
        let slug = model.replacingOccurrences(of: "\"", with: "")
        return minimalModelInfo(slug: slug.isEmpty ? "gpt-5" : slug)
    }

    private func sampleModelTurn() async throws -> ModelTurn {
        if let modelSampler {
            return try await modelSampler(harnessIncludeTools)
        }
        return try await modelGateway.streamComplete(includeTools: harnessIncludeTools)
    }

    private func dispatchSageTool(
        name: String,
        callId: String,
        argumentsJSON: String
    ) async -> String? {
        let output: String
        do {
            if let invokeHarnessTool {
                output = try await invokeHarnessTool(
                    ToolCallProposal(id: callId, name: name, argumentsJSON: argumentsJSON)
                )
            } else {
                output = "ERROR: Sage execute tool invoke is not attached"
            }
        } catch {
            output = "ERROR: \(error.localizedDescription)"
        }
        await recordHarnessToolResult(
            callID: callId,
            name: name,
            argumentsJSON: argumentsJSON,
            output: output
        )
        return output
    }

    /// Writes the tool result the next `sampleModelTurn` reads. `runTurn`
    /// keeps its own function-call output; the transcript is this commit.
    private func recordHarnessToolResult(
        callID: String,
        name: String,
        argumentsJSON: String,
        output: String
    ) async {
        let failed = output.hasPrefix("ERROR:")
        state.workspaceChanges.record(
            toolName: name,
            argumentsJSON: argumentsJSON,
            result: output,
            succeeded: !failed
        )
        if !failed, name == "load_skill",
           let skill = SkillToolExecutor.loadSkillName(from: argumentsJSON) {
            state.activatedSkillNames.insert(skill)
        }
        let protected = name == "load_skill" || name == "load_skill_resource"
        if var plan = planProgress.plan ?? state.activeTask?.pendingPlan {
            if let index = plan.steps.firstIndex(where: { $0.toolCallID == callID }) {
                plan.steps[index].status = failed ? .failed : .succeeded
                plan.steps[index].result = output
            }
            let done = !plan.steps.contains { $0.status == .pending || $0.status == .running }
            if done {
                planProgress.clear()
            } else {
                planProgress.update(plan)
            }
            _ = await taskStore.commit(
                appendEvents: [
                    AgentEvent(
                        kind: .toolResult,
                        content: output,
                        toolCallID: callID,
                        protected: protected
                    ),
                ],
                deleteEventIDs: [],
                mutate: { task in
                    task.pendingPlan = done ? nil : plan
                    task.pendingPrompt = nil
                    task.status = .active
                }
            )
        } else {
            _ = await taskStore.commit(
                appendEvents: [
                    AgentEvent(
                        kind: .toolResult,
                        content: output,
                        toolCallID: callID,
                        protected: protected
                    ),
                ],
                deleteEventIDs: []
            ) { _ in }
        }
    }

    /// Approval, retry, and declined-step resume. The round was counted when the model emitted it.
    func resumePausedBatch(retryFailedSteps: Bool) async {
        await runPausedBatch(retryFailedSteps: retryFailedSteps)
    }

    func finishWithoutMoreTools() async {
        if hasUnexecutedPendingBatch {
            guard await discardUnexecutedPendingBatch() else { return }
        } else {
            guard await taskStore.clearPendingPrompt() else { return }
        }
        if useHarnessRunTurn {
            harnessIncludeTools = false
            attachExecuteHarness()
            await runHarnessTurn()
            harnessIncludeTools = true
            return
        }
        await Turn.run(self, includeTools: false)
    }

    func handleTurn(_ turn: ModelTurn) async {
        switch await consume(turn) {
        case .finished:
            return
        case .needsFollowUp:
            await Turn.run(self, includeTools: true)
        }
    }

    func willSample(includeTools: Bool) async {
        state.enterThinking()
        await modelGateway.compactBeforeSampling(includeTools: includeTools)
        await ensureMCPConnected?()
        if let pending = GuardianInputBudget.checkPending(
            events: state.events,
            usableTokens: PromptBudget.forModel(GuardianReviewerConfig.resolveLive().model).usableTokens
        ) {
            abortReason = pending
        }
        if abortReason == nil, !sessionStartConsumed {
            sessionStartConsumed = true
            let start = await HookRuntime.sessionStart(
                projectRoot: projectRoot,
                source: pendingAttachSessionStartSource
                    ?? ExecuteHarnessAttach.inferredSessionStartSource(
                        historyEmpty: !state.events.contains(where: { $0.kind == .userInput })
                    ),
                sessionId: harnessSession?.threadId.description ?? "",
                cwd: projectRoot?.path,
                model: harnessTurnContext?.model ?? modelGateway.settings.snapshot(for: .execute).model,
                permissionMode: hookPermissionMode(
                    harnessTurnContext?.approvalPolicy ?? .onRequest
                )
            )
            if start.shouldStop {
                abortReason = start.additionalContexts.first ?? "Hook denied this turn."
            } else {
                await injectHookContexts(start.additionalContexts)
            }
        }
        if abortReason == nil, !userPromptSubmitConsumed {
            userPromptSubmitConsumed = true
            let lastUser = state.events.last(where: { $0.kind == .userInput })?.content ?? ""
            let submit = await HookRuntime.userPromptSubmit(
                lastUser,
                projectRoot: projectRoot,
                sessionId: harnessSession?.threadId.description ?? "",
                turnId: harnessTurnContext?.subId ?? "",
                cwd: projectRoot?.path,
                model: harnessTurnContext?.model ?? modelGateway.settings.snapshot(for: .execute).model,
                permissionMode: hookPermissionMode(
                    harnessTurnContext?.approvalPolicy ?? .onRequest
                )
            )
            if submit.shouldStop {
                abortReason = submit.additionalContexts.first ?? "Hook denied this turn."
            } else {
                await injectHookContexts(submit.additionalContexts)
            }
        }
    }

    func didCancel() async {
        if !useHarnessRunTurn {
            _ = await HookRuntime.interrupt(
                projectRoot: projectRoot,
                sessionId: harnessSession?.threadId.description ?? "",
                turnId: harnessTurnContext?.subId ?? "",
                cwd: projectRoot?.path,
                model: harnessTurnContext?.model ?? "",
                permissionMode: hookPermissionMode(
                    harnessTurnContext?.approvalPolicy ?? .onRequest
                )
            )
            _ = await HookRuntime.sessionEnd(
                projectRoot: projectRoot,
                sessionId: harnessSession?.threadId.description ?? "",
                cwd: projectRoot?.path
            )
        }
        streaming.clear()
        await handleStop?(nil)
    }

    func didFail(_ error: Error) async {
        if !useHarnessRunTurn {
            _ = await HookRuntime.sessionEnd(
                projectRoot: projectRoot,
                sessionId: harnessSession?.threadId.description ?? "",
                cwd: projectRoot?.path
            )
        }
        let partial = streaming.currentVisibleText
        streaming.clear()
        await taskStore.markFailed(error.localizedDescription, partialReply: partial)
    }

    private func injectHookContexts(_ contexts: [String]) async {
        let events = contexts.compactMap { text -> AgentEvent? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : AgentEvent(kind: .userInput, content: trimmed)
        }
        guard !events.isEmpty else { return }
        _ = await taskStore.commit(appendEvents: events, deleteEventIDs: [], mutate: { _ in })
    }

    func pauseForToolRoundLimit() async {}

    private func installHarnessMcpBridge(on session: Session) {
        if session.services.mcpVisibleTools.isEmpty, let catalog = mcpVisibleCatalog?() {
            session.services.mcpVisibleTools = catalog
        }
        session.services.ensureMcpConnected = { [weak self] in
            await self?.ensureMCPConnected?()
        }
        session.services.reconnectMcp = { [weak self] in
            await self?.reconnectMCP?()
        }
        session.services.disconnectMcp = { [weak self] names in
            await self?.disconnectMCP?(names)
        }
        session.services.mcpToolTransport = { [weak self] request in
            guard let self else {
                throw McpToolCallFailure("MCP transport is gone")
            }
            let invoke = await self.invokeHarnessTool
            guard let invoke else {
                throw McpToolCallFailure("MCP transport is not attached")
            }
            let qualified = "mcp__\(request.serverName)__\(request.toolName)"
            let text = try await invoke(
                ToolCallProposal(
                    id: UUID().uuidString,
                    name: qualified,
                    argumentsJSON: request.argumentsJSON
                )
            )
            let failed = text.hasPrefix("ERROR:")
            return callToolResult(fromTransportText: text, isError: failed)
        }
    }

    private func runHarnessTurn() async {
        await harnessSession?.ensureMcpConnected()
        harnessTurnSettled = false
        guard let session = harnessSession else { return }
        let context = harnessTurnContext ?? TurnContext()
        let token = harnessCancellation ?? CancellationToken()
        await session.spawnTask(
            RegularSessionTask(),
            turnContext: context,
            input: harnessInput,
            cancellationToken: token
        )
        if harnessTurnSettled {
            return
        }
        if token.isCancelled || session.lastTurnAbortReason != nil {
            await didCancel()
            return
        }
        if let error = session.lastTaskError {
            await didFail(error)
            return
        }
        await onCandidateReply?(session.lastTaskAgentMessage ?? "")
    }

    func sample(includeTools: Bool) async throws -> ModelTurn {
        if let abortReason {
            throw HarnessToolError.rejected(abortReason)
        }
        if let modelSampler {
            return try await modelSampler(includeTools)
        }
        return try await modelGateway.streamComplete(includeTools: includeTools)
    }

    private var projectRoot: URL? {
        if case .project(let root) = state.pathGuardPolicy { return root }
        return nil
    }

    var hasUnexecutedPendingBatch: Bool {
        let plan = planProgress.plan ?? state.activeTask?.pendingPlan
        guard let plan else { return false }
        return plan.steps.contains { $0.status == .pending || $0.status == .running }
    }

    private func runPausedBatch(retryFailedSteps: Bool) async {
        if useHarnessRunTurn {
            await resumeHarnessBatch(retryFailedSteps: retryFailedSteps)
            return
        }
        let outcome = await runToolBatch?(retryFailedSteps) ?? .persistFailed
        guard outcome == .succeeded else { return }
        await Turn.run(self, includeTools: true)
    }

    /// Re-admit the pending plan and let `runTurn` dispatch whatever is left.
    private func resumeHarnessBatch(retryFailedSteps: Bool) async {
        guard let turn = await prepareHarnessResume(retryFailedSteps: retryFailedSteps) else { return }
        if !turn.toolCalls.isEmpty {
            resumeToolTurn = turn
        }
        attachExecuteHarness()
        await runHarnessTurn()
    }

    /// Resets interrupted steps and returns the calls `runTurn` still needs to run.
    private func prepareHarnessResume(retryFailedSteps: Bool) async -> ModelTurn? {
        guard var plan = planProgress.plan ?? state.activeTask?.pendingPlan else { return nil }
        let errorEventIDs = retryFailedSteps
            ? ToolBatchExecutor.errorToolResultIDs(in: state.events, matching: plan)
            : []
        let succeededCallIDs = AgentEventHelpers.successfulToolCallIDs(in: state.events)
        for index in plan.steps.indices {
            if succeededCallIDs.contains(plan.steps[index].toolCallID) {
                plan.steps[index].status = .succeeded
                continue
            }
            let status = plan.steps[index].status
            let reopen = retryFailedSteps
                ? status == .failed || status == .skipped || status == .running
                : status == .running
            if reopen {
                plan.steps[index].status = .pending
                plan.steps[index].result = nil
            }
        }
        guard await taskStore.commit(
            appendEvents: [],
            deleteEventIDs: errorEventIDs,
            mutate: { task in
                task.pendingPlan = plan
                task.pendingPrompt = nil
                task.status = .active
            }
        ) else { return nil }
        planProgress.replace(plan)
        state.enterExecuting()
        let calls = plan.steps.compactMap { step -> ToolCallProposal? in
            guard step.status == .pending else { return nil }
            return ToolCallProposal(
                id: step.toolCallID,
                name: step.toolName,
                argumentsJSON: step.argumentsJSON
            )
        }
        return ModelTurn(content: nil, toolCalls: calls)
    }

    @discardableResult
    func discardUnexecutedPendingBatch() async -> Bool {
        guard hasUnexecutedPendingBatch else { return true }
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: state.events)
        guard await taskStore.commit(
            appendEvents: [],
            deleteEventIDs: retractIDs,
            mutate: { task in
                task.pendingPlan = nil
                task.pendingPrompt = nil
                task.status = .active
            }
        ) else { return false }
        return true
    }

    func consume(_ turn: ModelTurn) async -> Turn.StepResult {
        if turn.toolCalls.isEmpty {
            if let prompt = await HookRuntime.stopContinuation(
                projectRoot: projectRoot,
                alreadyActive: stopHookActive,
                sessionId: harnessSession?.threadId.description ?? "",
                turnId: harnessTurnContext?.subId ?? "",
                cwd: projectRoot?.path,
                model: harnessTurnContext?.model ?? "",
                permissionMode: hookPermissionMode(
                    harnessTurnContext?.approvalPolicy ?? .onRequest
                ),
                lastAssistantMessage: turn.content
            ) {
                stopHookActive = true
                guard await taskStore.commit(
                    appendEvents: [AgentEvent(kind: .userInput, content: prompt)],
                    deleteEventIDs: [],
                    mutate: { _ in }
                ) else { return .finished }
                return .needsFollowUp
            }
            await onCandidateReply?(
                turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            return .finished
        }

        switch await screenMutations(turn) {
        case .refusedAll:
            toolBatchCount += 1
            return .needsFollowUp

        case .proceed(let turn):
            return await runToolTurn(turn, recordAssistant: true)

        case .proceedAfterRefusal(let turn):
            return await runToolTurn(turn, recordAssistant: false)
        }
    }

    private func runToolTurn(_ turn: ModelTurn, recordAssistant: Bool) async -> Turn.StepResult {
        guard await persistIncomingToolBatch(
            turn,
            pendingPrompt: nil,
            recordAssistant: recordAssistant
        ) else { return .finished }
        toolBatchCount += 1
        let outcome = await runToolBatch?(false) ?? .persistFailed
        return outcome == .succeeded ? .needsFollowUp : .finished
    }

    private enum MutationScreen {
        /// Every call was a mutation on a non-act turn. Errors are already in the transcript.
        case refusedAll
        /// Run these calls. Refused siblings, if any, already have error results.
        case proceed(ModelTurn)
        /// Assistant message and refusal results are already committed.
        case proceedAfterRefusal(ModelTurn)
    }

    /// Observe / answer turns never run mutating tools. Mixed batches keep the
    /// reads and record an error for each write before the runner starts.
    private func screenMutations(_ turn: ModelTurn) async -> MutationScreen {
        let kind = state.activeTask?.workPlan?.kind
        guard kind != .act else { return .proceed(turn) }
        var failures: [(ToolCallProposal, String)] = []
        var allowed: [ToolCallProposal] = []
        for call in turn.toolCalls {
            do {
                try ToolInvocationDispatcher.assertMutatingToolsAllowed(
                    for: call.name,
                    workPlanKind: kind
                )
                allowed.append(call)
            } catch {
                failures.append((call, error.localizedDescription))
            }
        }
        guard !failures.isEmpty else { return .proceed(turn) }

        let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedCalls = turn.toolCalls.map { call in
            ToolCallRecord(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON)
        }
        let assistant = AgentEvent(
            kind: .assistantResponse,
            content: summary,
            toolCalls: storedCalls
        )
        let results = failures.map { call, message in
            AgentEvent(
                kind: .toolResult,
                content: "ERROR: \(message)",
                toolCallID: call.id
            )
        }
        guard await taskStore.commit(
            appendEvents: [assistant] + results,
            deleteEventIDs: [],
            mutate: { task in
                task.pendingPlan = nil
                task.pendingPrompt = nil
                task.status = .active
            }
        ) else { return .refusedAll }
        streaming.clear()
        if allowed.isEmpty {
            planProgress.clear()
            return .refusedAll
        }
        return .proceedAfterRefusal(ModelTurn(content: turn.content, toolCalls: allowed))
    }

    private func persistIncomingToolBatch(
        _ turn: ModelTurn,
        pendingPrompt: AgentPendingPrompt? = nil,
        recordAssistant: Bool = true
    ) async -> Bool {
        let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedCalls = turn.toolCalls.map { call in
            ToolCallRecord(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON)
        }
        let batch = ToolBatchExecutor.makePlan(
            from: turn.toolCalls,
            summary: summary,
            pathGuardPolicy: state.pathGuardPolicy
        )
        let assistant = AgentEvent(
            kind: .assistantResponse,
            content: summary,
            toolCalls: storedCalls
        )
        guard await taskStore.commit(
            appendEvents: recordAssistant ? [assistant] : [],
            deleteEventIDs: [],
            mutate: { task in
                task.pendingPlan = batch
                if let pendingPrompt {
                    task.pendingPrompt = pendingPrompt
                    task.status = .awaitingApproval
                } else {
                    task.status = .active
                }
            }
        ) else { return false }

        streaming.clear()
        planProgress.replace(batch)
        return true
    }
}
