//
//  handlers.swift
//  Sage
//
//  Port of codex-rs/core/src/session/handlers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  App-target Session loop: interrupt, user input, mailbox, compact,
//  shutdown. Realtime / elicitation / approval replies stay on
//  ThreadSession. A started regular turn is spawned so the loop can
//  keep receiving steer and interrupt.
//

import CodexAsyncUtils
import CodexProtocol
import Foundation

extension Session {
    func runSubmissionLoop() async {
        var shutdownReceived = false
        while let submission = await inboxRecv() {
            let shouldExit = await dispatchSubmission(submission)
            submission.ack?.signal()
            if shouldExit {
                shutdownReceived = true
                break
            }
        }
        let leftovers = inboxCloseAndDrain()
        for leftover in leftovers {
            leftover.ack?.signal()
            failLeftover(leftover)
        }
        if !shutdownReceived {
            await finishShutdown(submissionId: lastSubmissionId ?? "")
        }
    }

    func handle(_ submission: Submission) async {
        _ = await dispatchSubmission(submission)
    }

    /// rust `interrupt`.
    func interruptTask() async {
        let hadActiveTurn = activeTurn != nil
        await abortAllTasks(reason: .interrupted)
        if !hadActiveTurn {
            services.mcpRuntime.markDirty()
        }
        await maybeStartTurnForPendingWork()
    }

    /// rust `maybe_start_turn_for_pending_work`.
    func maybeStartTurnForPendingWork(subId: String? = nil) async {
        if state.shuttingDown { return }
        if hasRunningTask { return }
        let hasMailboxTrigger = inputQueue.hasTriggerTurnMailboxItems()
        let hasSessionPending = inputQueue.hasSessionPendingItems()
        guard hasSessionPending || hasMailboxTrigger else { return }
        let turnId = subId ?? UUID().uuidString
        let (input, _) = inputQueue.getPendingInputWithStartOptions(activeTurn)
        guard !input.isEmpty else { return }
        startDetachedTask(
            RegularSessionTask(),
            turnContext: newTurnContext(subId: turnId),
            input: input
        )
    }

    func startDetachedTask(
        _ task: SessionTask,
        turnContext: TurnContext,
        input: [SessionTurnInput]
    ) {
        if hasRunningTask { return }
        let token = CancellationToken()
        if activeTurn == nil {
            activeTurn = ActiveTurn()
        }
        activeTurn?.task = RunningTask(
            kind: task.kind,
            turnContext: turnContext,
            cancellationToken: token
        )
        Task { [weak self] in
            guard let self else { return }
            await self.startTask(
                task,
                turnContext: turnContext,
                input: input,
                cancellationToken: token
            )
            self.notifyIdleIfNeeded()
        }
    }

    static func shutdownSessionRuntime(_ session: Session) async {
        session.state.shuttingDown = true
    }

    fileprivate func inboxRecv() async -> Submission? {
        await submissionInboxRecv()
    }

    fileprivate func inboxCloseAndDrain() -> [Submission] {
        submissionInboxCloseAndDrain()
    }
}

extension Session {
    fileprivate func dispatchSubmission(_ submission: Submission) async -> Bool {
        switch submission.op {
        case .interrupt:
            await interruptTask()
            return false
        case .shutdown:
            await finishShutdown(submissionId: submission.id)
            return true
        case .userInput(let item):
            inputQueue.enqueue(item)
            await maybeStartTurnForPendingWork(subId: submission.id)
            return false
        case .interAgent(let communication):
            inputQueue.enqueueMailboxCommunication(communication)
            if communication.triggerTurn {
                await maybeStartTurnForPendingWork(subId: submission.id)
            }
            return false
        case .compact:
            await abortAllTasks(reason: .replaced)
            startDetachedTask(
                CompactSessionTask(),
                turnContext: newTurnContext(subId: submission.id),
                input: []
            )
            return false
        }
    }

    fileprivate func finishShutdown(submissionId: String) async {
        state.shuttingDown = true
        let turn = activeTurn?.task?.turnContext
        await abortAllTasks(reason: .interrupted)
        await runSessionEndHook(sess: self, turnContext: turn)
        sendEventRaw(Event(id: submissionId, msg: .shutdownComplete))
        closeEventMailbox()
        notifyIdleIfNeeded()
    }

    fileprivate func failLeftover(_ submission: Submission) {
        switch submission.op {
        case .userInput, .interAgent, .compact, .interrupt, .shutdown:
            break
        }
    }
}
