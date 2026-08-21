//
//  TurnCoordinator+Loop.swift
//  Sage
//

import Foundation

extension TurnCoordinator {
    /// Plan sub-agent. Confirm only when the strategy will change the Mac.
    func presentWorkPlan(for userText: String, autoConfirm: Bool) async {
        do {
            try Task.checkCancellation()
            let catalogNames = (skillCatalog()?.enabledSkills ?? []).map(\.name)
            let workPlan = try await planner.propose(
                userText: userText,
                skillAppendix: skillRecall.cachedResult?.text ?? "",
                allowedSkillNames: catalogNames
            )
            try Task.checkCancellation()
            guard await taskStore.commit(
                appendEvents: [],
                deleteEventIDs: [],
                mutate: { task in
                    task.workPlan = workPlan
                    task.status = workPlan.requiresConfirmation ? .awaitingApproval : .active
                }
            ) else { return }

            applyThreadOffer(from: workPlan)

            if workPlan.requiresConfirmation, !autoConfirm {
                state.enterAwaitingConfirmation()
                return
            }
            planApproved = true
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
        if let plan = state.activeTask?.pendingPlan ?? planProgress.plan {
            planProgress.replace(plan)
            await executeToolBatch?(true)
            return
        }
        if state.activeTask?.workPlan?.requiresConfirmation == true, !planApproved {
            state.enterAwaitingConfirmation()
            return
        }

        guard settings.isConfigured else {
            state.enterFailed(message: ModelClientError.notConfigured.localizedDescription)
            return
        }
        guard !state.events.isEmpty else { return }

        await execute.start()
    }

    func runModelTurn() async {
        if state.activeTask?.workPlan == nil,
           let userText = state.events.last(where: { $0.kind == .userInput })?.content {
            await presentWorkPlan(for: userText, autoConfirm: false)
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
        guard await persistClearedPendingPrompt() else { return }
        await execute.continueWithTools()
    }

    func finishWithoutMoreToolRounds() async {
        await execute.finishWithoutMoreTools()
    }

    func pauseForToolRoundLimit() async {
        await execute.pauseForToolRoundLimit()
    }

    @discardableResult
    func persistClearedPendingPrompt() async -> Bool {
        guard state.pendingPrompt != nil || state.activeTask?.pendingPrompt != nil else {
            return true
        }
        return await taskStore.commit(
            appendEvents: [],
            deleteEventIDs: []
        ) { task in
                task.pendingPrompt = nil
        }
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
        if workPlan?.kind == .answer {
            await finalizeAssistantText(draft, considerPersist: false)
            return
        }

        do {
            try Task.checkCancellation()
            if !draft.isEmpty {
                streaming.flush(draft)
            }
            let verdict = try await reviewer.evaluate()
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
            // A reviewer failure should not hide a finished execute pass.
            state.reviewFeedback = nil
            await finalizeAssistantText(draft, considerPersist: true)
        }
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
        guard await taskStore.commit(
            appendEvents: [AgentEvent(kind: .assistantResponse, content: reply)],
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
    }
}
