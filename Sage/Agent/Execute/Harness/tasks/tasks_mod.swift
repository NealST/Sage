//
//  tasks_mod.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SessionTask plus Session.spawnTask / startTask / onTaskFinished /
//  abortAllTasks. `RegularSessionTask` runs `runTurn`. Sage RegularTask
//  still owns ExecuteTurnLoop until AgentRuntime switches.
//

import CodexAsyncUtils
import CodexCore
import CodexProtocol
import CodexThreadStore
import Foundation

let gracefulInterruptionTimeoutMs: UInt64 = 100

enum InterruptedTurnHistoryMarker: Equatable, Sendable {
    case disabled
    case contextualUser
    case developer

    static func fromConfig(_ config: Config, multiAgentVersion: MultiAgentVersion) -> InterruptedTurnHistoryMarker {
        guard config.agentInterruptMessageEnabled else { return .disabled }
        return multiAgentVersion == .v2 ? .developer : .contextualUser
    }
}

func interruptedTurnHistoryMarker(_ marker: InterruptedTurnHistoryMarker) -> ResponseItem? {
    switch marker {
    case .disabled:
        return nil
    case .contextualUser:
        return TurnAborted(guidance: TurnAborted.interruptedGuidance).asResponseItem()
    case .developer:
        return TurnAborted(guidance: TurnAborted.interruptedDeveloperGuidance).asResponseItem()
    }
}

protocol SessionTask: AnyObject, Sendable {
    var kind: TaskKind { get }
    func run(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async throws -> String?
}

typealias SessionTaskResult = String?

extension Session {
    /// rust `Session::spawn_task`: replace the in-flight turn, then start.
    func spawnTask(
        _ task: SessionTask,
        turnContext: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken = CancellationToken()
    ) async {
        await abortAllTasks(reason: .replaced)
        state.clearConnectorSelection()
        await startTask(
            task,
            turnContext: turnContext,
            input: input,
            cancellationToken: cancellationToken
        )
    }

    /// rust `Session::start_task`. Tokio spawn / OTel / agent-control wait.
    func startTask(
        _ task: SessionTask,
        turnContext: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken = CancellationToken()
    ) async {
        await activatePluginSelection(turnContext)
        let cancellation = cancellationToken
        let (pendingItems, _) = inputQueue.drainMailboxInputItems()
        if activeTurn == nil {
            activeTurn = ActiveTurn()
        }
        guard let turnState = activeTurn?.turnState else { return }
        inputQueue.extendPendingInputForTurnState(turnState, input: pendingItems)
        await emitTurnStartLifecycle(
            turnContext,
            tokenUsageAtTurnStart: nil,
            phase: .beforeTaskRegistration
        )
        let running = RunningTask(
            kind: task.kind,
            turnContext: turnContext,
            cancellationToken: cancellation
        )
        activeTurn?.task = running

        do {
            let result = try await task.run(
                session: self,
                context: turnContext,
                input: input,
                cancellationToken: cancellation.childToken()
            )
            if !cancellation.isCancelled {
                await onTaskFinished(turnContext, result: .success(result))
            }
        } catch {
            if !cancellation.isCancelled {
                await onTaskFinished(turnContext, result: .failure(error))
            }
        }
        running.done = true
    }

    func abortAllTasks(reason: TurnAbortReason) async {
        guard let active = activeTurn else { return }
        let hadTask = active.task != nil
        let turnContext = active.task?.turnContext
        active.task?.cancellationToken?.cancel()
        active.task?.done = true
        active.task = nil
        if hadTask {
            lastTurnAbortReason = reason
            if let turnContext {
                await emitTurnAbortLifecycle(reason.rawValue)
                sendEvent(
                    turnContext,
                    .turnAborted(TurnAbortedEvent(turnId: turnContext.subId, reason: reason))
                )
            }
            inputQueue.clearPending(active)
            activeTurn = nil
        }
    }

    func onTaskFinished(_ turnContext: TurnContext, result: Result<String?, Error>) async {
        let lastAgentMessage: String?
        let abortReason: TurnAbortReason?
        switch result {
        case .success(let message):
            lastAgentMessage = message
            abortReason = nil
        case .failure(let error):
            let err = (error as? CodexErr) ?? CodexErr.fatal(String(describing: error))
            if err.details == .turnAborted {
                lastAgentMessage = nil
                abortReason = .interrupted
            } else {
                emitTurnErrorLifecycle(turnContext, error: err)
                sendEvent(turnContext, .error(ErrorEvent(message: err.localizedDescription)))
                lastAgentMessage = nil
                abortReason = nil
            }
        }
        lastTaskAgentMessage = lastAgentMessage
        lastTurnAbortReason = abortReason
        if case .failure(let error) = result, abortReason == nil {
            lastTaskError = error
        } else {
            lastTaskError = nil
        }

        guard let turnState = activeTurn?.turnState else { return }
        activeTurn?.task = nil
        let pendingInput = inputQueue.takePendingInputForTurnState(turnState)
        _ = await runHooksAndRecordInputs(
            sess: self,
            turnContext: turnContext,
            modelInfo: turnContext.captureCurrentModelInfo(),
            input: pendingInput,
            persistContext: .standard
        )
        if let abortReason {
            sendEvent(
                turnContext,
                .turnAborted(TurnAbortedEvent(turnId: turnContext.subId, reason: abortReason))
            )
        } else {
            sendEvent(
                turnContext,
                .turnComplete(TurnCompleteEvent(turnId: turnContext.subId))
            )
        }
        await emitTurnStopLifecycle()
        activeTurn = nil
    }
}
