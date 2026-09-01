//
//  AgentRuntime+Actions.swift
//  Sage
//

import Foundation

extension AgentRuntime {
    func confirmWorkPlan() async {
        guard !state.shouldDisableConfirmationActions else { return }
        guard turnChrome == .workPlan else { return }
        _ = await operations.run { await self.turns.startExecution() }
    }

    func confirmToolBatch() async {
        guard !state.shouldDisableConfirmationActions else { return }
        _ = await operations.run { await self.executeCurrentPlanUnlocked(retryFailedSteps: false) }
    }

    func confirmToolRoundLimit() async {
        guard !state.shouldDisableConfirmationActions else { return }
        guard turnChrome == .toolRoundLimit else { return }
        _ = await operations.run { await self.turns.extendAndContinueToolRounds() }
    }

    func finishToolRoundLimit() async {
        guard !state.shouldDisableConfirmationActions else { return }
        guard turnChrome == .toolRoundLimit else { return }
        _ = await operations.run { await self.turns.finishWithoutMoreToolRounds() }
    }

    func confirmToolApproval(scope: SessionToolApprovalScope) async {
        guard !state.shouldDisableConfirmationActions else { return }
        guard case .toolApproval(_, let name, let args, _) = state.pendingPrompt else { return }
        let hookDecision = await preToolUseDecision(name: name, argumentsJSON: args)
        if case .deny(let reason) = hookDecision {
            await failToolApproval(reason: "Blocked by PreToolUse hook: \(reason)")
            return
        }
        await recordToolApproval(
            scope: scope,
            name: name,
            argumentsJSON: args,
            hookApproval: {
                if case .ask(let approval) = hookDecision { return approval }
                return nil
            }()
        )
    }

    private func recordToolApproval(
        scope: SessionToolApprovalScope,
        name: String,
        argumentsJSON args: String,
        hookApproval: PreToolUseApproval?
    ) async {
        let key = SessionToolAllowlist.combinationKey(name: name, argumentsJSON: args)
        SecurityAuditLogger.approval(toolName: name, scope: scope, key: key)
        recordCapabilityApproval(scope: scope, name: name, argumentsJSON: args)
        if let hookApproval {
            recordHookApproval(
                scope: scope,
                name: name,
                argumentsJSON: args,
                approval: hookApproval
            )
        }
        _ = await operations.run {
            await self.executeCurrentPlanUnlocked(retryFailedSteps: false)
        }
    }

    private func recordCapabilityApproval(
        scope: SessionToolApprovalScope,
        name: String,
        argumentsJSON args: String
    ) {
        switch scope {
        case .once:
            state.sessionAllowlist.allowCapabilityOnce(
                name: name,
                argumentsJSON: args,
                policy: state.pathGuardPolicy,
                skills: host.catalogSkills,
                mcpTools: mcpHub?.mcpTools ?? []
            )

        case .task:
            state.sessionAllowlist.allowThisTask(
                name: name,
                argumentsJSON: args,
                policy: state.pathGuardPolicy,
                scopeID: state.authorizationScopeID,
                skills: host.catalogSkills,
                mcpTools: mcpHub?.mcpTools ?? []
            )

        case .always:
            state.sessionAllowlist.allowLongTerm(
                name: name,
                argumentsJSON: args,
                policy: state.pathGuardPolicy,
                skills: host.catalogSkills,
                mcpTools: mcpHub?.mcpTools ?? []
            )
        }
    }

    private func recordHookApproval(
        scope: SessionToolApprovalScope,
        name: String,
        argumentsJSON args: String,
        approval: PreToolUseApproval
    ) {
        switch scope {
        case .once:
            state.sessionAllowlist.allowHookOnce(
                name: name,
                argumentsJSON: args,
                hookIdentity: approval.identity
            )

        case .task:
            state.sessionAllowlist.allowHookForTask(
                name: name,
                argumentsJSON: args,
                hookIdentity: approval.identity,
                scopeID: state.authorizationScopeID
            )

        case .always:
            state.sessionAllowlist.allowHookLongTerm(
                name: name,
                argumentsJSON: args,
                hookIdentity: approval.identity,
                label: approval.reason
            )
        }
    }

    func skipToolApproval() async {
        guard !state.shouldDisableConfirmationActions else { return }
        await failToolApproval(reason: "User skipped this tool.")
    }

    private func failToolApproval(reason: String) async {
        guard case .toolApproval(let callID, let name, let args, _) = state.pendingPrompt else { return }
        SecurityAuditLogger.approvalDenied(
            toolName: name,
            key: SessionToolAllowlist.combinationKey(name: name, argumentsJSON: args)
        )
        guard var plan = planProgress.plan ?? state.activeTask?.pendingPlan,
              let index = plan.steps.firstIndex(where: { $0.toolCallID == callID })
        else {
            _ = await operations.run {
                _ = await self.taskStore.commit(
                    appendEvents: [],
                    deleteEventIDs: []
                ) { task in
                    task.pendingPrompt = nil
                }
            }
            return
        }
        plan.steps[index].status = .failed
        plan.steps[index].result = reason
        let planToCommit = plan
        let event = AgentEvent(
            kind: .toolResult,
            content: "ERROR: \(reason) Continue with the remaining work or pick another approach.",
            toolCallID: callID
        )
        planProgress.update(planToCommit)
        _ = await operations.run {
            guard await self.taskStore.commit(
                appendEvents: [event],
                deleteEventIDs: [],
                mutate: { task in
                    task.pendingPlan = planToCommit
                    task.pendingPrompt = nil
                    task.status = .active
                }
            ) else { return }
            await self.executeCurrentPlanUnlocked(retryFailedSteps: false)
        }
    }

    func cancelPendingPlan() async {
        guard !state.shouldDisableConfirmationActions else { return }
        guard operations.begin() else { return }
        defer { operations.end() }
        let taskID = state.activeTaskID
        let cancelled = await performCancelPendingPlan()
        if cancelled, let taskID {
            await onTaskSettled?(taskID, nil, .cancelled)
        }
    }

    func resetPhaseToIdle() {
        state.clearCompletedPhase()
        if case .failed = state.phase, state.activeTask?.pendingPlan == nil, !planProgress.hasPlan {
            state.enterIdle()
        }
    }

    func dismissFailure() async {
        guard case .failed = state.phase else { return }
        if let plan = state.activeTask?.pendingPlan ?? planProgress.plan {
            guard operations.begin() else { return }
            defer { operations.end() }
            planProgress.replace(plan)
            state.enterAwaitingConfirmation()
            let taskID = state.activeTaskID
            if await performCancelPendingPlan(), let taskID {
                await onTaskSettled?(taskID, nil, .cancelled)
            }
            return
        }
        state.enterIdle()
    }

    func runModelTurn() async {
        await turns.runModelTurn()
    }

    func selectSkillActivation(named name: String) async {
        guard let choice = skills.tips.choosePrompt,
              choice.candidates.contains(where: { $0.name == name })
        else { return }

        _ = await operations.run {
            self.skills.tips.dismissChoose()
            self.skills.enqueueConsolidateIfNeeded(candidates: choice.candidates)
            self.state.enterThinking()
            await self.skillRecall.loadSkillsByName([name])
            self.skillRecall.refreshCatalogWithoutRematch(query: choice.queryText)
            await self.runModelTurn()
        }
    }

    func skipSkillActivation() async {
        guard let choice = skills.tips.choosePrompt else { return }

        _ = await operations.run {
            self.skills.tips.dismissChoose()
            self.skills.enqueueConsolidateIfNeeded(candidates: choice.candidates)
            self.state.enterThinking()
            await self.runModelTurn()
        }
    }

    @discardableResult
    func prepareSkillsForTurn(query: String) -> Bool {
        skillRecall.prepareSkillsForTurn(query: query)
    }

    func noteSkillsActivated(_ names: Set<String>) {
        state.activatedSkillNames.formUnion(names)
    }

    func executeCurrentPlanUnlocked(retryFailedSteps: Bool = false) async {
        let plan = planProgress.plan ?? state.activeTask?.pendingPlan
        guard let initialPlan = plan else { return }
        await ToolBatchExecutor.execute(
            initialPlan: initialPlan,
            services: makeExecuteServices(),
            retryFailedSteps: retryFailedSteps
        )
    }

    @discardableResult
    func performCancelPendingPlan() async -> Bool {
        guard case .awaitingConfirmation = state.phase else { return false }
        if case .toolRoundLimit = state.pendingPrompt {
            if state.activeTask?.pendingPlan != nil || planProgress.hasPlan {
                return await ToolBatchExecutor.cancelPendingPlan(services: makeExecuteServices())
            }
            guard await taskStore.commit(
                appendEvents: [],
                deleteEventIDs: [],
                mutate: { task in
                    task.pendingPrompt = nil
                }
            ) else { return false }
            state.enterIdle()
            return true
        }
        return await ToolBatchExecutor.cancelPendingPlan(services: makeExecuteServices())
    }

    // MARK: - Task store façades used by UI / AppState

    @discardableResult
    func beginNewTask(relatedTo relatedTaskIDs: [UUID] = []) async -> UUID? {
        await taskStore.beginNewTask(relatedTo: relatedTaskIDs)
    }

    func activateTask(_ id: UUID) async {
        guard id != state.activeTaskID else { return }
        if state.isBusy {
            await operations.cancelInFlight()
        }
        await taskStore.activateTask(id)
    }

    @discardableResult
    func commit(
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        mutate: (inout TaskRecord) -> Void = { _ in }
    ) async -> Bool {
        await taskStore.commit(
            appendEvents: appendEvents,
            deleteEventIDs: deleteEventIDs,
            mutate: mutate
        )
    }
}
