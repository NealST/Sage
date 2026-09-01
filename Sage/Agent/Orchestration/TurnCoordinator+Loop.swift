//
//  TurnCoordinator+Loop.swift
//  Sage
//

import Foundation

extension TurnCoordinator {
    /// Plan classifies intent. `answer` replies immediately; `act` confirms first.
    func presentWorkPlan(for userText: String) async {
        do {
            try Task.checkCancellation()
            let catalogNames = (skillCatalog()?.enabledSkills ?? []).map(\.name)
            let proposed = try await planner.propose(
                userText: userText,
                skillAppendix: skillRecall.cachedResult?.text ?? "",
                allowedSkillNames: catalogNames
            )
            let workPlan = proposed.plan
            streaming.setReservingWorkPlan(false)
            try Task.checkCancellation()
            let leadIn = proposed.leadIn.trimmingCharacters(in: .whitespacesAndNewlines)
            let leadInEvents: [AgentEvent] =
                workPlan.kind != .answer && !leadIn.isEmpty
                ? [AgentEvent(kind: .assistantResponse, content: leadIn)]
                : []
            guard await taskStore.commit(
                appendEvents: leadInEvents,
                deleteEventIDs: [],
                mutate: { task in
                    task.workPlan = workPlan
                    task.status = workPlan.requiresConfirmation ? .awaitingApproval : .active
                }
            ) else { return }
            if workPlan.kind != .answer {
                streaming.flush("")
            }

            applyThreadOffer(from: workPlan)

            if workPlan.requiresConfirmation {
                state.enterAwaitingConfirmation()
                return
            }
            planApproved = true
            if let reply = workPlan.directReply {
                await finalizeAssistantText(reply, considerPersist: false)
                return
            }
            await activateRecalledSkills(from: workPlan)
            await execute.start()
        } catch is CancellationError {
            streaming.clear()
            await handleStop?(nil)
        } catch {
            streaming.clear()
            await taskStore.markFailed(error.localizedDescription)
        }
    }

    func performRetry() async {
        switch retryPath() {
        case .retryToolBatch:
            guard let plan = state.activeTask?.pendingPlan ?? planProgress.plan else { return }
            planProgress.replace(plan)
            await executeToolBatch?(true)

        case .confirmWorkPlan:
            state.enterAwaitingConfirmation()

        case .resumeModelTurn:
            await runModelTurn()

        case .none:
            if !settings.isConfigured {
                state.enterFailed(message: ModelClientError.notConfigured.localizedDescription)
            }
        }
    }

    /// Where Retry should resume. `nil` means nothing to do (or not configured).
    func retryPath() -> TurnRetryPath? {
        if state.activeTask?.pendingPlan != nil || planProgress.hasPlan {
            return .retryToolBatch
        }
        if state.activeTask?.workPlan?.requiresConfirmation == true, !planApproved {
            return .confirmWorkPlan
        }
        guard settings.isConfigured else { return nil }
        guard !state.events.isEmpty else { return nil }
        return .resumeModelTurn
    }

    func runModelTurn() async {
        if state.activeTask?.workPlan == nil,
           let userText = state.events.last(where: { $0.kind == .userInput })?.content {
            await presentWorkPlan(for: userText)
            return
        }
        await execute.start()
    }

    func handleTurn(_ turn: ModelTurn) async {
        await execute.handleTurn(turn)
    }

    var canOfferMoreTools: Bool {
        execute.canOfferMoreTools
    }

    func notePlanApproved() {
        planApproved = true
    }

    func extendAndContinueToolRounds() async {
        execute.extendToolBatchLimit()
        guard await taskStore.clearPendingPrompt() else { return }
        await execute.continueWithTools()
    }

    func finishWithoutMoreToolRounds() async {
        await execute.finishWithoutMoreTools()
    }

    func pauseForToolRoundLimit() async {
        await execute.pauseForToolRoundLimit()
    }

    func startExecution() async {
        planApproved = true
        if let workPlan = state.activeTask?.workPlan {
            await activateRecalledSkills(from: workPlan)
        }
        await execute.start()
    }

    /// Review sub-agent. Accept finishes; revise sends execute around again.
    func reviewAndFinish(_ draft: String) async {
        let workPlan = state.activeTask?.workPlan
        if workPlan?.skipsReview == true {
            await finalizeAssistantText(draft, considerPersist: false)
            return
        }

        do {
            try Task.checkCancellation()
            if !draft.isEmpty {
                streaming.flush(draft)
            }
            let verdict = try await reviewer.evaluate(
                draft: draft,
                changes: state.workspaceChanges.snapshot()
            )
            try Task.checkCancellation()

            if verdict.decision == .accept || reviewRounds >= ReviewAgent.maxRevisions {
                state.reviewFeedback = nil
                await finalizeAssistantText(draft, considerPersist: true)
                return
            }

            reviewRounds += 1
            state.reviewFeedback = verdict.feedback.nilIfEmpty
                ?? "The result does not fully match the plan. Finish the remaining work."
            execute.resetLoop()
            await execute.start()
        } catch is CancellationError {
            streaming.clear()
            await handleStop?(nil)
        } catch {
            await presentReviewFailure(draft: draft, message: error.localizedDescription)
        }
    }

    func retryFailedReview() async {
        guard case .reviewFailed(let draft, _) = state.pendingPrompt else { return }
        guard await taskStore.clearPendingPrompt() else { return }
        await reviewAndFinish(draft)
    }

    func acceptFailedReview() async {
        guard case .reviewFailed(let draft, _) = state.pendingPrompt else { return }
        guard await taskStore.clearPendingPrompt() else { return }
        state.reviewFeedback = nil
        await finalizeAssistantText(draft, considerPersist: true)
    }

    func persistSteerTurn(_ turn: QueuedUserTurn) async -> Bool {
        let event = AgentEvent(
            kind: .userInput,
            content: turn.text,
            attachments: turn.attachments
        )
        let retractIDs = AgentEventHelpers.unexecutedToolProposalIDs(in: state.events)
        guard await taskStore.commit(
            appendEvents: [event],
            deleteEventIDs: retractIDs,
            mutate: { task in
                task.status = .active
                task.pendingPlan = nil
                task.pendingPrompt = nil
            }
        ) else { return false }
        state.clearPendingPrompt()
        latestUserEventID = event.id
        state.steerInstruction = turn.text
        reviewRounds = 0
        execute.resetLoop()
        return true
    }

    func continueAfterSteer() async {
        state.turnInput.pendingSteer = nil
        if state.activeTask?.workPlan == nil {
            let text = state.events.last { $0.kind == .userInput }?.content ?? ""
            await presentWorkPlan(for: text)
            return
        }
        planApproved = true
        await execute.start()
    }

    func presentReviewFailure(draft: String, message: String) async {
        let prompt = AgentPendingPrompt.reviewFailed(draft: draft, message: message)
        state.pendingPrompt = prompt
        _ = await taskStore.commit(appendEvents: [], deleteEventIDs: []) { task in
            task.pendingPrompt = prompt
        }
        state.enterAwaitingConfirmation()
    }

    func finalizeAssistantText(
        _ text: String,
        emptyFallback: String = "I couldn't produce a reply.",
        considerPersist: Bool = false
    ) async {
        let reply = text.isEmpty ? emptyFallback : text
        let alreadyConsidered = state.activeTask?.skillPersistConsidered == true
        let settledID = state.activeTaskID
        let settledPlan = state.activeTask?.workPlan
        let changes = state.workspaceChanges.snapshot()
        let settledChanges = changes.isEmpty ? nil : changes
        guard await taskStore.commit(
            appendEvents: [
                AgentEvent(
                    kind: .assistantResponse,
                    content: reply,
                    workspaceChanges: settledChanges
                ),
            ],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .completed
                task.pendingPlan = nil
                task.pendingPrompt = nil
                if !keepWorkPlanAfterComplete {
                    task.workPlan = nil
                }
                task.skillPersistConsidered = true
            }
        ) else { return }

        streaming.clear()
        state.reviewFeedback = nil
        state.steerInstruction = nil
        state.workspaceChanges.reset()
        state.clearPendingPrompt()
        state.lastAssistantText = reply
        state.enterCompleted(summary: reply)
        planProgress.clear()
        topicCoordinator.generateTopicIfNeeded(for: state.activeTask)

        if let settledID {
            await onTaskSettled?(settledID, settledPlan, .completed)
        }

        if considerPersist, !alreadyConsidered, !keepWorkPlanAfterComplete, let task = state.activeTask {
            skills.considerPersistenceAfterReview(for: task) { [planner] in
                await planner.judgePersistence(task: task)
            }
        }
    }

    func applyThreadOffer(from workPlan: WorkPlan) {
        guard allowDriftOffer,
              workPlan.threadAdvice == .offerFresh,
              state.topicDriftOffer == nil,
              let task = state.activeTask,
              task.events.count >= TopicDriftDetector.minimumPriorEvents,
              state.suppressedDriftOfferTaskID != task.id,
              let userEventID = latestUserEventID
        else { return }

        let label = workPlan.threadLabel
            ?? TopicDriftDetector.threadLabel(
                topic: task.topic,
                abstract: task.abstract,
                summary: task.summary
            )
            ?? "this task"
        state.topicDriftOffer = TopicDriftOffer(
            taskID: task.id,
            triggeringUserEventID: userEventID,
            topicLabel: label
        )
        state.contextHint = nil
    }

    func activateRecalledSkills(from workPlan: WorkPlan) async {
        guard !workPlan.skillNames.isEmpty else { return }
        await skillRecall.loadSkillsByName(workPlan.skillNames)
    }

    func resetTurn() {
        execute.resetLoop()
        planApproved = false
        reviewRounds = 0
        state.reviewFeedback = nil
        state.steerInstruction = nil
        state.workspaceChanges.reset()
        if let id = state.activeTaskID {
            turnLoopByTask[id] = TurnLoopState()
            turnLoopTaskID = id
        }
    }

    /// Load loop flags for the window’s current task. Stashes the previous thread.
    func adoptActiveTask() {
        let newID = state.activeTaskID
        if turnLoopTaskID == newID { return }
        if let oldID = turnLoopTaskID {
            turnLoopByTask[oldID] = TurnLoopState(
                planApproved: planApproved,
                reviewRounds: reviewRounds
            )
        }
        turnLoopTaskID = newID
        let stored = newID.flatMap { turnLoopByTask[$0] } ?? TurnLoopState()
        planApproved = stored.planApproved
        reviewRounds = stored.reviewRounds
        execute.resetLoop()
        latestUserEventID = state.events.last { $0.kind == .userInput }?.id
    }

    func dropTurnLoop(for id: UUID) {
        turnLoopByTask.removeValue(forKey: id)
        if turnLoopTaskID == id {
            turnLoopTaskID = nil
            planApproved = false
            reviewRounds = 0
            execute.resetLoop()
        }
    }
}

enum TurnRetryPath: Equatable {
    case retryToolBatch
    case confirmWorkPlan
    case resumeModelTurn
}
