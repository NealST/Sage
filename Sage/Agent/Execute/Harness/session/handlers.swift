//
//  handlers.swift
//  Sage
//
//  Port of codex-rs/core/src/session/handlers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  App-target Session loop: interrupt, user input, mailbox, compact,
//  review, thread settings, turn settings, conditional interrupt, recovery,
//  suspend-and-shutdown, user-input answers, permission answers, dynamic-tool
//  answers, exec approvals, patch approvals, MCP refresh, user-config reload,
//  background-terminal cleanup, elicitation replies, and denied-action
//  approvals, shutdown. An idle user submission starts `RegularSessionTask` with
//  that submission's start options. Mailbox mail starts a turn when it
//  sets `triggerTurn`, or when the thread has an outstanding durable
//  sleep; queue-only mail inherits the reference context's cyber
//  program. Realtime replies stay on
//  ThreadSession. A started regular turn is spawned so the loop can
//  keep receiving steer and interrupt.
//

import CodexAsyncUtils
import CodexCore
import CodexProtocol
import Foundation

func triggersTurn(_ input: SessionTurnInput) -> Bool {
    if case .interAgentCommunication(let mail) = input, mail.triggerTurn {
        return true
    }
    return false
}

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
    ///
    /// Mailbox mail wakes an idle session when a message sets `triggerTurn`,
    /// or when any mail is waiting and the thread is durably asleep.
    /// Session-pending user input is started by `acceptUserInput` instead.
    func maybeStartTurnForPendingWork(subId: String? = nil) async {
        if state.shuttingDown { return }
        if hasRunningTask { return }
        let hasMailbox = inputQueue.hasPendingMailboxItems()
        let hasMailboxTrigger = inputQueue.hasTriggerTurnMailboxItems()
        guard hasMailbox, hasMailboxTrigger || hasOutstandingDurableSleep() else { return }
        let turnId = subId ?? UUID().uuidString
        var (input, startOptions) = inputQueue.getPendingInputWithStartOptions(activeTurn)
        guard !input.isEmpty else { return }
        if !input.contains(where: triggersTurn) {
            startOptions.cyberAccessProgram = referenceCyberAccessProgram()
        }
        let turnContext = newTurnContext(
            subId: turnId,
            options: NewTurnContextOptions(
                start: startOptions,
                initiatingAgentPath: initiatingAgentPath(
                    in: input,
                    parentTurnId: startOptions.parentTurnId
                )
            )
        )
        lastStartedTurnContext = turnContext
        lastStartedTurnId = turnContext.subId
        startDetachedTask(
            RegularSessionTask(),
            turnContext: turnContext,
            input: input
        )
    }

    /// Idle user input becomes a regular turn. Input that arrives while a
    /// turn is sampling stays queued for that turn's next sample.
    func acceptUserInput(_ item: SessionTurnInput, submission: Submission) async {
        if state.shuttingDown { return }
        if hasRunningTask {
            inputQueue.enqueue(item)
            return
        }
        let turnContext = newTurnContext(
            subId: submission.id,
            options: NewTurnContextOptions(start: submission.startOptions)
        )
        lastStartedTurnContext = turnContext
        lastStartedTurnId = turnContext.subId
        startDetachedTask(
            RegularSessionTask(),
            turnContext: turnContext,
            input: [item]
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
        case .interruptIfNoPendingInput(let turnId):
            await interruptTurnIfNoPendingInput(turnId: turnId, ack: submission.ack)
            return false
        case .shutdown:
            await finishShutdown(submissionId: submission.id)
            return true
        case .suspendTurnAndShutdown:
            return await suspendTurnAndShutdown(submissionId: submission.id)
        case .userInput(let item):
            await acceptUserInput(item, submission: submission)
            return false
        case .interAgent(let communication):
            inputQueue.enqueueMailboxCommunication(
                communication,
                startOptions: submission.startOptions
            )
            if communication.triggerTurn || hasOutstandingDurableSleep() {
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
        case .review(let request):
            await startReview(submissionId: submission.id, request: request)
            return false
        case .threadSettings(let overrides):
            await updateThreadSettings(submissionId: submission.id, overrides: overrides)
            return false
        case .turnSettings(let turnId, let update):
            lastTurnSettingsOutcome = applyTurnSettings(turnId: turnId, update: update)
            return false
        case .recoverTurn(let request):
            await recoverTurn(request)
            return false
        case .userInputAnswer(let id, let response):
            notifyUserInputResponse(id: id, response: response)
            return false
        case .requestPermissionsResponse(let id, let response):
            notifyRequestPermissionsResponse(id: id, response: response)
            return false
        case .dynamicToolResponse(let id, let response):
            notifyDynamicToolResponse(id: id, response: response)
            return false
        case .execApproval(let id, let turnId, let decision):
            await handleExecApproval(id: id, turnId: turnId, decision: decision)
            return false
        case .patchApproval(let id, let decision):
            await handlePatchApproval(id: id, decision: decision)
            return false
        case .refreshMcpServers:
            refreshMcpServers()
            return false
        case .reloadUserConfig:
            await reloadUserConfigLayer()
            return false
        case .cleanBackgroundTerminals:
            await closeUnifiedExecProcesses()
            return false
        case .resolveElicitation(let serverName, let requestId, let decision, let content, let meta):
            await resolveElicitation(
                serverName: serverName,
                id: requestId,
                response: submittedElicitationResponse(
                    decision: decision, content: content, meta: meta)
            )
            return false
        case .approveGuardianDeniedAction(let event):
            approveGuardianDeniedAction(event)
            return false
        }
    }

    func finishShutdown(submissionId: String) async {
        state.shuttingDown = true
        await stopMcpPrewarmWorker()
        let turn = activeTurn?.task?.turnContext
        await abortAllTasks(reason: .interrupted)
        await runSessionEndHook(sess: self, turnContext: turn)
        sendEventRaw(Event(id: submissionId, msg: .shutdownComplete))
        closeEventMailbox()
        notifyIdleIfNeeded()
    }

    fileprivate func failLeftover(_ submission: Submission) {
        switch submission.op {
        case .userInput, .interAgent, .compact, .review, .threadSettings, .turnSettings,
             .recoverTurn, .userInputAnswer, .requestPermissionsResponse, .dynamicToolResponse,
             .execApproval, .patchApproval, .refreshMcpServers, .reloadUserConfig,
             .cleanBackgroundTerminals, .resolveElicitation, .approveGuardianDeniedAction,
             .interrupt,
             .interruptIfNoPendingInput, .suspendTurnAndShutdown, .shutdown:
            break
        }
    }

    /// rust `approve_guardian_denied_action`. A denied assessment becomes one
    /// developer fragment. An active turn queues it; otherwise it is history.
    /// Any other status is ignored. A serialization failure drops the approval.
    func approveGuardianDeniedAction(_ event: GuardianAssessmentEvent) {
        guard event.status == .denied else { return }
        guard let approved = prettyApprovedGuardianAction(event.action) else { return }
        injectNoNewTurn([GuardianApprovedAction(text: approved).asResponseItem()])
    }
}

func prettyApprovedGuardianAction(_ action: GuardianAssessmentAction) -> String? {
    guard let data = try? JSONEncoder().encode(action),
          let actionValue = try? JSONDecoder().decode(CodexProtocol.JSONValue.self, from: data)
    else { return nil }
    return prettyJSONValue(
        .object([
            "action": actionValue,
            "outcome": .string("allowed"),
        ])
    )
}

func prettyJSONValue(_ value: CodexProtocol.JSONValue, indent: Int = 0) -> String {
    switch value {
    case .array(let values):
        let rendered = values.map { prettyJSONValue($0, indent: indent + 2) }
        return prettyJSONCollection(rendered, indent: indent, brackets: ("[", "]"))

    case .object(let object):
        let lines = object.keys.sorted().map { key in
            let rendered = prettyJSONValue(object[key] ?? .null, indent: indent + 2)
            return "\(CodexProtocol.JSONValue.string(key).encodedString()): \(rendered)"
        }
        return prettyJSONCollection(lines, indent: indent, brackets: ("{", "}"))

    default:
        return value.encodedString()
    }
}

private func prettyJSONCollection(_ lines: [String], indent: Int, brackets: (String, String)) -> String {
    if lines.isEmpty { return brackets.0 + brackets.1 }
    let pad = String(repeating: " ", count: indent + 2)
    let close = String(repeating: " ", count: indent)
    let body = lines.map { "\(pad)\($0)" }.joined(separator: ",\n")
    return "\(brackets.0)\n\(body)\n\(close)\(brackets.1)"
}
