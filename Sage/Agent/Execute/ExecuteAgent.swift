//
//  ExecuteAgent.swift
//  Sage
//
//  Sub-agent: follow the work plan and ReAct (tools → results → next call).
//

import Foundation

@MainActor
final class ExecuteAgent {
    private let state: AgentSessionState
    private let planProgress: PlanProgress
    private let taskStore: AgentTaskStore
    private let modelGateway: AgentModelGateway
    private let streaming: StreamingTextPump

    private var executeTools: (() async -> Void)?
    private var onCandidateReply: ((String) async -> Void)?
    private var handleStop: ((AgentPlan?) async -> Void)?

    private(set) var toolBatchCount = 0
    private(set) var toolBatchLimit = ExecuteAgent.defaultToolBatchLimit
    nonisolated static let defaultToolBatchLimit = 8
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
        executeTools: @escaping () async -> Void,
        onCandidateReply: @escaping (String) async -> Void,
        handleStop: @escaping (AgentPlan?) async -> Void
    ) {
        self.executeTools = executeTools
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

    func start() async {
        await runModelTurn(includeTools: true)
    }

    func continueWithTools() async {
        if hasUnexecutedPendingBatch {
            toolBatchCount += 1
            await executeTools?()
            return
        }
        await runModelTurn(includeTools: true)
    }

    func finishWithoutMoreTools() async {
        if hasUnexecutedPendingBatch {
            guard await discardUnexecutedPendingBatch() else { return }
        } else {
            guard await persistClearedPendingPrompt() else { return }
        }
        await runModelTurn(includeTools: false)
    }

    func handleTurn(_ turn: ModelTurn) async {
        if !turn.toolCalls.isEmpty {
            let atCap = !canOfferMoreTools
            let prompt: AgentPendingPrompt? = atCap
                ? .toolRoundLimit(currentLimit: toolBatchLimit, nextLimit: nextToolBatchLimit)
                : nil
            guard await persistIncomingToolBatch(turn, pendingPrompt: prompt) else { return }
            if atCap {
                state.enterAwaitingConfirmation()
                return
            }
            toolBatchCount += 1
            await executeTools?()
            return
        }

        await onCandidateReply?(
            turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
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

    private var hasUnexecutedPendingBatch: Bool {
        let plan = planProgress.plan ?? state.activeTask?.pendingPlan
        guard let plan else { return false }
        return plan.steps.contains { $0.status == .pending || $0.status == .running }
    }

    private func persistIncomingToolBatch(
        _ turn: ModelTurn,
        pendingPrompt: AgentPendingPrompt? = nil
    ) async -> Bool {
        let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedCalls = turn.toolCalls.map {
            ToolCallRecord(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON)
        }
        let batch = ToolBatchExecutor.makePlan(
            from: turn.toolCalls,
            summary: summary,
            pathGuardPolicy: state.pathGuardPolicy
        )
        guard await taskStore.commit(
            appendEvents: [
                AgentEvent(
                    kind: .assistantResponse,
                    content: summary,
                    toolCalls: storedCalls
                ),
            ],
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
        return true
    }

    @discardableResult
    private func discardUnexecutedPendingBatch() async -> Bool {
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

    private func persistClearedPendingPrompt() async -> Bool {
        guard state.pendingPrompt != nil || state.activeTask?.pendingPrompt != nil else {
            return true
        }
        return await taskStore.commit(
            appendEvents: [],
            deleteEventIDs: [],
            mutate: { task in
                task.pendingPrompt = nil
            }
        )
    }

    private func runModelTurn(includeTools: Bool) async {
        state.enterThinking()
        do {
            try Task.checkCancellation()
            let turn = try await modelGateway.streamComplete(includeTools: includeTools)
            try Task.checkCancellation()
            await handleTurn(turn)
        } catch is CancellationError {
            streaming.clear()
            await handleStop?(nil)
        } catch {
            streaming.clear()
            await taskStore.markFailed(error.localizedDescription)
        }
    }
}
