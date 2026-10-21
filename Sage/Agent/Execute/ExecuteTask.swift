//
//  ExecuteTask.swift
//  Sage
//
//  Sage addition (no codex counterpart).
//
//  `RegularTask` is the Execute entry on `TurnCoordinator`: it attaches a
//  harness Session from AgentSessionState on `start()`. Sampling and tool
//  dispatch go through `runTurn`. Follow-up samples stream the prompt
//  `buildPrompt` assembled, through the ModelClientSession that turn already
//  opened. Sage's system text and tool schemas are written onto that prompt
//  first. Provider text and usage reach `runTurn` as they arrive.
//  Function calls stay out until HUD admission. A host without
//  `/responses` falls back to chat completions. HUD approval is
//  admitted before dispatch so the card never waits inside `runTurn`.
//  Attach binds the allowlist ApprovalStore, the session
//  ParallelAdmission, and HookRuntime project/skills so
//  `registry.dispatch` owns Pre/PostToolUse. Resume replays the
//  pending calls through that same dispatch.
//

import SageAsyncUtils
import SageCore
import SageProtocol
import SageThreadStore
import Foundation

/// Execute entry on `TurnCoordinator`.
@MainActor
final class RegularTask {
    let state: AgentSessionState
    let planProgress: PlanProgress
    let taskStore: AgentTaskStore
    let modelGateway: AgentModelGateway
    let streaming: StreamingTextPump

    /// One in-flight tool batch. Returns when the batch pauses, fails, or finishes.
    /// Sampling the next model step is `session/turn.swift`, not this closure.
    var onCandidateReply: ((String) async -> Void)?
    var handleStop: ((AgentPlan?) async -> Void)?
    /// Connect enabled MCP servers that are not already running. Sage starts
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
    /// Sole creator/owner of the persistent per-task harness Session (M3).
    /// Provided by `TurnCoordinator.ensureTaskHarness()`.
    var harnessProvider: (() -> TaskHarness?)?
    /// The harness this turn's context and input were assembled against.
    var turnHarness: TaskHarness?
    var harnessTurnContext: TurnContext?
    var harnessInput: [SessionTurnInput] = []
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
    var resumeToolTurn: ModelTurn?
    var harnessIncludeTools = true

    private(set) var toolBatchCount = 0
    /// Rounds in a row where every proposed call was refused. At the cap the
    /// turn collapses to a tool-free text answer instead of looping.
    private var consecutiveRefusalRounds = 0
    private static let maxConsecutiveRefusalRounds = 3

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
        onCandidateReply: @escaping (String) async -> Void,
        handleStop: @escaping (AgentPlan?) async -> Void,
        ensureMCPConnected: (() async -> Void)? = nil,
        reconnectMCP: (() async -> Void)? = nil,
        disconnectMCP: (([String]) async -> Void)? = nil,
        invokeHarnessTool: ((ToolCallProposal) async throws -> String)? = nil
    ) {
        self.onCandidateReply = onCandidateReply
        self.handleStop = handleStop
        self.ensureMCPConnected = ensureMCPConnected
        self.reconnectMCP = reconnectMCP
        self.disconnectMCP = disconnectMCP
        self.invokeHarnessTool = invokeHarnessTool
    }

    func resetLoop() {
        toolBatchCount = 0
        consecutiveRefusalRounds = 0
    }

    /// Sage `RegularTask::run` → `run_turn`.
    func start() async {
        state.workspaceChanges.beginIfNeeded(replaying: state.events)
        attachExecuteHarness(.lastUserInput)
        await runHarnessTurn()
    }

    func continueWithTools() async {
        if hasUnexecutedPendingBatch {
            toolBatchCount += 1
            await runPausedBatch(retryFailedSteps: false)
            return
        }
        attachExecuteHarness(.none)
        await runHarnessTurn()
    }

    /// M3: rework after a must-fix / optional-improve verdict. Same task
    /// session — the review verdict is already in its history — with the
    /// feedback submitted as an explicit user turn. The synthetic input
    /// lives on the session only, never in `state.events`, so the UI
    /// transcript is unchanged.
    func startRework(_ userText: String) async {
        state.workspaceChanges.beginIfNeeded(replaying: state.events)
        resetLoop()
        attachExecuteHarness(.text(userText))
        await runHarnessTurn()
    }

    /// Which user input an execute turn submits. `.lastUserInput` re-rails a
    /// new turn (start / steer); `.none` continues on session history that
    /// already carries the context; `.text` submits a synthetic user turn
    /// (review rework) recorded on the session alone.
    enum ExecuteTurnInputMode {
        case lastUserInput
        case none
        case text(String)
    }

    func attachExecuteHarness(_ mode: ExecuteTurnInputMode = .lastUserInput) {
        let cwd = projectRoot?.path ?? FileManager.default.currentDirectoryPath
        let settings = modelGateway.settings.snapshot(for: .execute)
        guard let harness = harnessProvider?(), !harness.isShutDown else { return }
        harness.prepareExecuteTurn()
        let turnContext = ExecuteHarnessAttach.makeTurnContext(
            cwd: cwd,
            model: settings.model,
            allowsMutation: state.activeTask?.workPlan?.kind == .act
        )
        turnContext.threadId = harness.threadId
        turnContext.sessionId = SessionId(harness.threadId)
        turnHarness = harness
        harnessTurnContext = turnContext
        switch mode {
        case .lastUserInput:
            if let event = state.events.last(where: { $0.kind == .userInput }),
               harness.recordedUserInputEventID != event.id {
                harness.recordedUserInputEventID = event.id
                harnessInput = [TurnInputBuilder.user(ExecuteHarnessAttach.userContents(from: event))]
            } else {
                harnessInput = []
            }
        case .none:
            harnessInput = []
        case .text(let text):
            harnessInput = [TurnInputBuilder.user([.text(text: text, textElements: [])])]
        }
    }

    enum OpenedSample {
        case buffered(LiveSample)
        case live(SageCore.ResponseStream)
    }

    /// Sampler and chat completions have no provider event list. Screen the
    /// batch, then synthesize the stream `runTurn` dispatches.
    func streamBuffered(_ sample: LiveSample) async -> SageCore.ResponseStream {
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
    func streamAdmittedTools(
        _ turn: ModelTurn,
        events: [SageResult<ResponseEvent>]? = nil,
        recordAssistant: Bool,
        countRound: Bool = true,
        replacePlan: Bool = true
    ) async -> SageCore.ResponseStream {
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
            consecutiveRefusalRounds = 0
            return .admit(Set(turn.toolCalls.map(\.id)))
        case .halted:
            recordHaltedBatchInSession(turn)
            consecutiveRefusalRounds += 1
            if consecutiveRefusalRounds >= Self.maxConsecutiveRefusalRounds {
                collapseToTextOnlyAnswer()
            }
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

    struct LiveSample {
        var turn: ModelTurn
        var events: [SageResult<ResponseEvent>]?
    }

    private func replay(_ sample: LiveSample) -> SageCore.ResponseStream {
        if let events = sample.events {
            return ExecuteHarnessAttach.replay(
                events,
                allowing: Set(sample.turn.toolCalls.map(\.id))
            )
        }
        return ExecuteHarnessAttach.responseStream(from: sample.turn)
    }

    func openModelSample(_ prompt: Prompt) async throws -> OpenedSample {
        let conversation = ExecuteHarnessAttach.agentEvents(from: prompt.input)
        harnessSampleConversations.append(conversation)
        if let modelSampler {
            do {
                return .buffered(
                    LiveSample(turn: try await modelSampler(harnessIncludeTools), events: nil)
                )
            } catch is CancellationError {
                throw SageErr.turnAborted
            }
        }
        let snapshot = modelGateway.settings.snapshot(for: .execute)
        if let harness = turnHarness,
           !harness.responsesTransportUnavailable(snapshot),
           let clientSession = harness.session.samplingClientSession ?? harness.session.services.modelClient?.newSession() {
            let session = harness.session
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
            } catch let error as SageErr where ExecuteHarnessAttach.responsesEndpointMissing(error) {
                harness.markResponsesTransportUnavailable(snapshot)
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

    func dispatchSageTool(
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

    /// Writes the tool result the next sampling round reads. `runTurn`
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
        harnessIncludeTools = false
        attachExecuteHarness(.none)
        await runHarnessTurn()
        harnessIncludeTools = true
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

    private func runHarnessTurn() async {
        // `collapseToTextOnlyAnswer` and `finishWithoutMoreTools` drop the
        // tool schemas for one turn; every settled turn hands them back.
        defer { harnessIncludeTools = true }
        if let session = turnHarness?.session {
            await session.ensureMcpConnected()
        }
        harnessTurnSettled = false
        guard let session = turnHarness?.session else { return }
        let context = harnessTurnContext ?? TurnContext()
        let token = CancellationToken()
        // Cancelled turns skip `onTaskFinished`, so without clearing, a
        // previous turn's outcome slots would decide this turn's result.
        session.lastTaskAgentMessage = nil
        session.lastTurnAbortReason = nil
        session.lastTaskError = nil
        await withTaskCancellationHandler {
            await session.spawnTask(
                RegularSessionTask(),
                turnContext: context,
                input: harnessInput,
                cancellationToken: token
            )
        } onCancel: {
            token.cancel()
        }
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
        await resumeHarnessBatch(retryFailedSteps: retryFailedSteps)
    }

    /// Re-admit the pending plan and let `runTurn` dispatch whatever is left.
    private func resumeHarnessBatch(retryFailedSteps: Bool) async {
        guard let turn = await prepareHarnessResume(retryFailedSteps: retryFailedSteps) else { return }
        if !turn.toolCalls.isEmpty {
            resumeToolTurn = turn
        }
        attachExecuteHarness(.none)
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
    /// The registry allowlist gate cannot replace this: Execute turns carry
    /// no allowlist, and unlike that gate these refusals are committed to the
    /// transcript so the UI shows why a batch was cut down. They are also
    /// recorded on the harness session: the filtered stream drops refused
    /// calls, and a sample that cannot see its own refusals re-proposes them.
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

        recordRefusedCallsInSession(failures)
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
            consecutiveRefusalRounds += 1
            if consecutiveRefusalRounds >= Self.maxConsecutiveRefusalRounds {
                collapseToTextOnlyAnswer()
            }
            return .refusedAll
        }
        consecutiveRefusalRounds = 0
        return .proceedAfterRefusal(ModelTurn(content: turn.content, toolCalls: allowed))
    }

    /// Refused calls never reach `runTurn` through the filtered stream, so
    /// the refusal rides the session history as a call plus error output.
    /// Without it the transcript commit is UI-only and the model never learns
    /// the batch was refused.
    private func recordRefusedCallsInSession(_ failures: [(ToolCallProposal, String)]) {
        guard let session = turnHarness?.session, !failures.isEmpty else { return }
        var items: [ResponseItem] = []
        for (call, message) in failures {
            items.append(.functionCall(
                id: nil,
                name: call.name,
                namespace: nil,
                arguments: call.argumentsJSON,
                encryptedFunctionArgs: nil,
                callId: call.id,
                internalChatMessageMetadataPassthrough: nil
            ))
            items.append(.functionCallOutput(
                id: nil,
                callId: call.id,
                name: nil,
                namespace: nil,
                output: .fromText("ERROR: \(message)"),
                internalChatMessageMetadataPassthrough: nil
            ))
        }
        session.recordConversationItems(harnessTurnContext ?? TurnContext(), items: items)
    }

    /// A halted batch recorded one terminal step (validation error, hook
    /// deny, or denied approval) and dropped every call from the stream.
    /// Feed each call's outcome back so the next sample sees why nothing ran.
    private func recordHaltedBatchInSession(_ turn: ModelTurn) {
        let resultsByID = Dictionary(
            state.events.compactMap { event -> (String, String)? in
                guard event.kind == .toolResult, let id = event.toolCallID else { return nil }
                return (id, event.content)
            },
            uniquingKeysWith: { _, last in last }
        )
        let failures = turn.toolCalls.map { call -> (ToolCallProposal, String) in
            guard let result = resultsByID[call.id] else {
                return (call, "Skipped: the batch was halted before this call ran.")
            }
            if result.hasPrefix("ERROR:") {
                return (
                    call,
                    String(result.dropFirst("ERROR:".count))
                        .trimmingCharacters(in: .whitespaces)
                )
            }
            return (call, result)
        }
        recordRefusedCallsInSession(failures)
    }

    /// The model keeps proposing refused batches. Drop the tool schemas for
    /// the follow-up sample and tell it to answer in plain text, so the turn
    /// ends with an explanation instead of a fourth refusal.
    /// `runHarnessTurn` restores tools when the turn settles.
    private func collapseToTextOnlyAnswer() {
        guard harnessIncludeTools else { return }
        harnessIncludeTools = false
        recordSessionGuidance(
            """
            Your last \(Self.maxConsecutiveRefusalRounds) tool batches were all refused. \
            Tool calls are disabled for this reply: answer in plain text. Explain what you \
            wanted to do and what the user must confirm or change before it can run.
            """
        )
    }

    private func recordSessionGuidance(_ text: String) {
        turnHarness?.session.recordConversationItems(
            harnessTurnContext ?? TurnContext(),
            items: [
                .message(
                    id: nil,
                    role: "user",
                    content: [.outputText(text: text)],
                    phase: nil,
                    internalChatMessageMetadataPassthrough: nil
                )
            ]
        )
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

/// Child SageThreads run tools through the same Live Execute invoke path.
final class ExecuteChildToolRunner: TurnToolRunner, @unchecked Sendable {
    weak var task: RegularTask?

    init(task: RegularTask) {
        self.task = task
    }

    func runTool(
        turnId: String,
        call: TurnFunctionCall,
        cancellation: CancellationToken
    ) async throws -> String {
        _ = turnId
        if cancellation.isCancelled { throw CancellationError() }
        let invoke = await task?.invokeHarnessTool
        guard let invoke else {
            throw SageErr.unsupportedOperation("child tool invoke is not attached")
        }
        return try await invoke(
            ToolCallProposal(id: call.callId, name: call.name, argumentsJSON: call.arguments)
        )
    }
}
