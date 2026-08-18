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
    static let maxToolBatches = 8

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
    }

    var canOfferMoreTools: Bool {
        toolBatchCount < Self.maxToolBatches
    }

    func start() async {
        await runModelTurn(includeTools: true)
    }

    func handleTurn(_ turn: ModelTurn) async {
        if !turn.toolCalls.isEmpty {
            if !canOfferMoreTools {
                let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty ?? "Stopped after the tool-round limit."
                await onCandidateReply?(text)
                return
            }

            toolBatchCount += 1
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
                    task.status = .active
                }
            ) else { return }

            streaming.clear()
            planProgress.replace(batch)
            await executeTools?()
            return
        }

        await onCandidateReply?(
            turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
