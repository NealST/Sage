//
//  regular.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/regular.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  Codex `RegularTask::run` calls `run_turn`, then repeats while the session
//  input queue still has user input. Sage keeps that queue on `TurnInputQueue`
//  and drains it from `AgentRuntime`; this task owns one execute episode.
//

import Foundation

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
    /// Test seam for `ModelClientSession::stream`. Production uses `modelGateway`.
    var modelSampler: ((Bool) async throws -> ModelTurn)?

    private(set) var toolBatchCount = 0
    private(set) var toolBatchLimit = RegularTask.defaultToolBatchLimit
    /// Safety valve, not the product loop. Raised above the old 8-batch stop.
    nonisolated static let defaultToolBatchLimit = 32
    nonisolated static let maxToolBatchLimit = 64

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
        handleStop: @escaping (AgentPlan?) async -> Void
    ) {
        self.runToolBatch = runToolBatch
        self.onCandidateReply = onCandidateReply
        self.handleStop = handleStop
    }

    func resetLoop() {
        toolBatchCount = 0
        toolBatchLimit = Self.defaultToolBatchLimit
    }

    var canOfferMoreTools: Bool {
        toolBatchCount < toolBatchLimit
    }

    var nextToolBatchLimit: Int {
        min(toolBatchLimit + Self.defaultToolBatchLimit, Self.maxToolBatchLimit)
    }

    func extendToolBatchLimit() {
        toolBatchLimit = nextToolBatchLimit
    }

    /// Codex `RegularTask::run` → `run_turn`.
    func start() async {
        state.workspaceChanges.beginIfNeeded(replaying: state.events)
        await Turn.run(self, includeTools: true)
    }

    func continueWithTools() async {
        if hasUnexecutedPendingBatch {
            toolBatchCount += 1
            await runPausedBatch(retryFailedSteps: false)
            return
        }
        await Turn.run(self, includeTools: true)
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
            guard canOfferMoreTools else {
                await pauseForToolRoundLimit()
                return
            }
            await Turn.run(self, includeTools: true)
        }
    }

    func willSample(includeTools: Bool) async {
        state.enterThinking()
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

    func pauseForToolRoundLimit() async {
        let prompt = AgentPendingPrompt.toolRoundLimit(
            currentLimit: toolBatchLimit,
            nextLimit: nextToolBatchLimit
        )
        guard await taskStore.commit(
            appendEvents: [],
            deleteEventIDs: [],
            mutate: { task in
                task.pendingPrompt = prompt
                task.status = .awaitingApproval
            }
        ) else { return }
        state.enterAwaitingConfirmation()
    }

    func sample(includeTools: Bool) async throws -> ModelTurn {
        if let modelSampler {
            return try await modelSampler(includeTools)
        }
        return try await modelGateway.streamComplete(includeTools: includeTools)
    }

    var hasUnexecutedPendingBatch: Bool {
        let plan = planProgress.plan ?? state.activeTask?.pendingPlan
        guard let plan else { return false }
        return plan.steps.contains { $0.status == .pending || $0.status == .running }
    }

    private func runPausedBatch(retryFailedSteps: Bool) async {
        let outcome = await runToolBatch?(retryFailedSteps) ?? .persistFailed
        guard outcome == .succeeded else { return }
        guard canOfferMoreTools else {
            await pauseForToolRoundLimit()
            return
        }
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
        let atCap = !canOfferMoreTools
        let prompt: AgentPendingPrompt? = atCap
            ? .toolRoundLimit(currentLimit: toolBatchLimit, nextLimit: nextToolBatchLimit)
            : nil
        guard await persistIncomingToolBatch(
            turn,
            pendingPrompt: prompt,
            recordAssistant: recordAssistant
        ) else { return .finished }
        if atCap {
            state.enterAwaitingConfirmation()
            return .finished
        }
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
