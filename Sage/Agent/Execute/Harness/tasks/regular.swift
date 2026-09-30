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
//  AgentSessionState on `start()`; live Execute still uses
//  ExecuteTurnLoop until `useHarnessRunTurn`. Tools go through
//  SageExecuteHandler → onSageToolCall → ExecuteServices.
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
    /// Test seam for `ModelClientSession::stream`. Production uses `modelGateway`.
    var modelSampler: ((Bool) async throws -> ModelTurn)?
    /// Prepared rust Session. Live Execute still uses `Turn.run` until
    /// `useHarnessRunTurn` is set.
    var harnessSession: Session?
    var harnessTurnContext: TurnContext?
    var harnessInput: [SessionTurnInput] = []
    var harnessCancellation: CancellationToken?
    /// Flip when tool dispatch is attached. Until then `start()` keeps `Turn.run`.
    var useHarnessRunTurn = false
    /// Live Sage tool invoke (ExecuteServices). Tests can stub this.
    var invokeHarnessTool: ((ToolCallProposal) async throws -> String)?

    private(set) var toolBatchCount = 0
    /// Codex `stop_hook_active`: a Stop hook continuation is not blocked again.
    private var stopHookActive = false
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
        invokeHarnessTool: ((ToolCallProposal) async throws -> String)? = nil
    ) {
        self.runToolBatch = runToolBatch
        self.onCandidateReply = onCandidateReply
        self.handleStop = handleStop
        self.ensureMCPConnected = ensureMCPConnected
        self.invokeHarnessTool = invokeHarnessTool
    }

    func resetLoop() {
        toolBatchCount = 0
        stopHookActive = false
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
        let model = modelGateway.settings.snapshot(for: .execute).model
        let snapshot = ExecuteHarnessAttach.snapshot(
            events: state.events,
            cwd: cwd,
            model: model,
            allowsMutation: state.activeTask?.workPlan?.kind == .act
        )
        let session = ExecuteHarnessAttach.makeSession(history: snapshot.history)
        bindHarnessSampling(session)
        harnessSession = session
        harnessTurnContext = ExecuteHarnessAttach.makeTurnContext(
            cwd: snapshot.cwd,
            model: snapshot.model,
            allowsMutation: snapshot.allowsMutation
        )
        harnessInput = snapshot.input
    }

    private func bindHarnessSampling(_ session: Session) {
        guard useHarnessRunTurn else { return }
        session.services.sageToolNames = modelGateway.availableToolDefinitions().map(\.name)
        session.services.onSageToolCall = { [weak self] name, callId, arguments in
            await self?.dispatchSageTool(name: name, callId: callId, argumentsJSON: arguments)
        }
        guard session.runSamplingStreamOverride == nil, session.runSamplingOverride == nil else {
            return
        }
        session.runSamplingStreamOverride = { [weak self] _ in
            let turn = try await MainActor.run {
                guard let self else {
                    throw CodexErr.fatal("execute harness sampler is gone")
                }
                return try await self.sampleModelTurn()
            }
            return ExecuteHarnessAttach.responseStream(from: turn)
        }
    }

    private func sampleModelTurn() async throws -> ModelTurn {
        if let modelSampler {
            return try await modelSampler(true)
        }
        return try await modelGateway.streamComplete(includeTools: true)
    }

    private func dispatchSageTool(
        name: String,
        callId: String,
        argumentsJSON: String
    ) async -> String? {
        do {
            if let invokeHarnessTool {
                return try await invokeHarnessTool(
                    ToolCallProposal(id: callId, name: name, argumentsJSON: argumentsJSON)
                )
            }
            return "ERROR: Sage execute tool invoke is not attached"
        } catch {
            return "ERROR: \(error.localizedDescription)"
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
            usableTokens: PromptBudget.forModel(modelGateway.settings.snapshot(for: .review).model).usableTokens
        ) {
            abortReason = pending
        }
        if abortReason == nil {
            abortReason = HookRuntime.sessionStartDenial(projectRoot: projectRoot)
        }
    }

    func didCancel() async {
        streaming.clear()
        await handleStop?(nil)
    }

    func didFail(_ error: Error) async {
        let partial = streaming.currentVisibleText
        streaming.clear()
        await taskStore.markFailed(error.localizedDescription, partialReply: partial)
    }

    func pauseForToolRoundLimit() async {}

    private func runHarnessTurn() async {
        guard let session = harnessSession else { return }
        let context = harnessTurnContext ?? TurnContext()
        let token = harnessCancellation ?? CancellationToken()
        await session.spawnTask(
            RegularSessionTask(),
            turnContext: context,
            input: harnessInput,
            cancellationToken: token
        )
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
        let outcome = await runToolBatch?(retryFailedSteps) ?? .persistFailed
        guard outcome == .succeeded else { return }
        await Turn.run(self, includeTools: true)
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
            if let prompt = HookRuntime.stopContinuation(
                projectRoot: projectRoot,
                alreadyActive: stopHookActive
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
