//
//  AgentRuntime.swift
//  Sage
//

import Foundation

@MainActor
@Observable
final class AgentRuntime {
    /// Full active task only — other tasks stay as lightweight summaries.
    private(set) var activeTask: TaskRecord?
    private(set) var recentSummaries: [TaskSummary] = []
    private(set) var activeTaskID: UUID?
    private(set) var phase: AgentPhase = .idle
    private(set) var lastAssistantText: String?
    /// Soft chip when Sage resumes related prior work (not ordinary continuity).
    private(set) var contextHint: String?
    private(set) var isBusy = false
    /// After dismissing the context chip, the next submit starts a clean task.
    private var forceFreshOnNextSubmit = false
    /// In-flight submit/confirm/retry work — cancelled by `stop()`.
    private var workTask: Task<Void, Never>?

    var events: [AgentEvent] {
        activeTask?.events ?? []
    }

    var availableTools: [ToolDefinition] {
        tools.definitions + (capabilities?.mcpToolDefinitions() ?? [])
    }

    var canRetryFailure: Bool {
        guard case .failed = phase else { return false }
        if activeTask?.pendingPlan != nil { return true }
        return !events.isEmpty
    }

    var canStop: Bool {
        guard isBusy else { return false }
        switch phase {
        case .thinking, .executing:
            return true
        default:
            return false
        }
    }

    var canStartFresh: Bool {
        guard !isBusy else { return false }
        switch phase {
        case .thinking, .executing:
            return false
        case .awaitingConfirmation:
            return true
        case .idle, .completed, .failed:
            return activeTask?.events.isEmpty == false
                || contextHint != nil
                || forceFreshOnNextSubmit
        }
    }

    var hasPendingPlan: Bool {
        if case .awaitingConfirmation = phase { return true }
        return activeTask?.pendingPlan != nil
    }

    /// Failed with a recoverable pending plan — composer should not accept new input.
    var blocksNewInput: Bool {
        if isBusy { return true }
        switch phase {
        case .thinking, .executing, .awaitingConfirmation:
            return true
        case .failed:
            return activeTask?.pendingPlan != nil
        case .idle, .completed:
            return false
        }
    }

    private let modelClient = ModelClient()
    private let tools: ToolRegistry
    private let taskRepository: any TaskRepository
    private let contextResolver: any TaskContextResolving
    private let settings: ModelSettings
    private weak var capabilities: CapabilityStore?

    private let systemPrompt = """
    You are Sage, a native macOS agent that helps the user get work done on their Mac.
    Prefer using tools for real actions (files, clipboard, apps, notifications).
    Keep plans small and concrete. Expand ~ paths. Stay inside the user's home directory for files.
    When rewriting text for the clipboard, use get_clipboard / set_clipboard.
    After tools run, you will see their results — then give a short clear summary of what happened.
    Reply in the same language the user uses.
    """

    init(
        settings: ModelSettings,
        tools: ToolRegistry,
        taskRepository: any TaskRepository,
        contextResolver: any TaskContextResolving,
        capabilities: CapabilityStore? = nil
    ) {
        self.settings = settings
        self.tools = tools
        self.taskRepository = taskRepository
        self.contextResolver = contextResolver
        self.capabilities = capabilities
    }

    func bootstrap() async {
        do {
            let snapshot = try await taskRepository.loadWorkspace()
            recentSummaries = snapshot.recentSummaries
            if let task = snapshot.activeTask {
                activeTask = task
                activeTaskID = task.id
                await restorePhaseFromActiveTask()
            } else {
                _ = await createAndActivateTask(relatedTo: [])
            }
        } catch {
            phase = .failed(message: "Could not open Sage’s local database: \(error.localizedDescription)")
        }
    }

    /// Starts a clean internal task boundary without exposing session management.
    @discardableResult
    func startFresh() async -> UUID? {
        guard beginOperation() else { return nil }
        defer { endOperation() }

        if case .awaitingConfirmation = phase {
            guard await performCancelPendingPlan() else { return nil }
        } else if let plan = activeTask?.pendingPlan {
            phase = .awaitingConfirmation(plan)
            guard await performCancelPendingPlan() else { return nil }
        }

        forceFreshOnNextSubmit = false
        contextHint = nil
        return await beginNewTask(relatedTo: [])
    }

    /// Hides the chip and forces the next submit onto a fresh task boundary.
    func dismissContextHint() {
        contextHint = nil
        forceFreshOnNextSubmit = true
    }

    /// Cancels in-flight model/tool work. Pending confirmation still uses Cancel.
    func stop() {
        guard canStop else { return }
        workTask?.cancel()
    }

    /// Entry point for a future context resolver. The UI does not expose task creation.
    @discardableResult
    func beginNewTask(relatedTo relatedTaskIDs: [UUID] = []) async -> UUID? {
        // Persist the closed prior task before switching memory.
        if var closing = activeTask {
            let retractIDs = unexecutedToolProposalIDs(in: closing.events)
            if !retractIDs.isEmpty {
                let deleteSet = Set(retractIDs)
                closing.events.removeAll { deleteSet.contains($0.id) }
            }
            if closing.status == .active || closing.status == .awaitingApproval {
                closing.status = .completed
            }
            closing.pendingPlan = nil
            closing.updatedAt = .now
            do {
                try await taskRepository.mutateTask(
                    closing,
                    appendEvents: [],
                    deleteEventIDs: retractIDs,
                    setActive: true
                )
                // Keep memory aligned with the closed snapshot if create fails next.
                activeTask = closing
                activeTaskID = closing.id
                refreshSummary(for: closing)
                phase = .idle
                lastAssistantText = nil
            } catch {
                phase = .failed(message: "Could not close the previous task: \(error.localizedDescription)")
                return nil
            }
        }
        return await createAndActivateTask(relatedTo: relatedTaskIDs)
    }

    /// Entry point for future semantic retrieval. Not surfaced as chat navigation.
    func activateTask(_ id: UUID) async {
        guard id != activeTaskID else { return }

        if var current = activeTask {
            if case .awaitingConfirmation(let plan) = phase {
                current.pendingPlan = plan
                current.status = .awaitingApproval
            }
            current.updatedAt = .now
            do {
                try await taskRepository.saveTaskState(current, setActive: false)
            } catch {
                phase = .failed(message: "Could not save task context: \(error.localizedDescription)")
                return
            }
        }

        do {
            guard let task = try await taskRepository.loadTask(id: id) else {
                phase = .failed(message: "Could not find that task context.")
                return
            }
            try await taskRepository.setActiveTaskID(id)
            activeTask = task
            activeTaskID = task.id
            refreshSummary(for: task)
            await restorePhaseFromActiveTask()
            contextHint = Self.hint(for: task)
        } catch {
            phase = .failed(message: "Could not restore task context: \(error.localizedDescription)")
        }
    }

    func eraseAllData() async -> Bool {
        guard !isBusy else { return false }
        do {
            try await taskRepository.eraseAllData()
            activeTask = nil
            activeTaskID = nil
            recentSummaries = []
            lastAssistantText = nil
            contextHint = nil
            forceFreshOnNextSubmit = false
            phase = .idle
            guard await createAndActivateTask(relatedTo: []) != nil else { return false }
            return true
        } catch {
            phase = .failed(message: "Could not erase local data: \(error.localizedDescription)")
            return false
        }
    }

    /// Retries the model turn after a failure without duplicating user input.
    func retryLastFailure() async {
        guard beginOperation() else { return }
        defer { endOperation(); workTask = nil }
        guard case .failed = phase else { return }

        let work = Task { @MainActor in
            await self.performRetry()
        }
        workTask = work
        await work.value
    }

    /// Returns `true` once the user message was accepted into history (draft can clear).
    @discardableResult
    func submit(_ userText: String) async -> Bool {
        guard beginOperation() else { return false }
        defer { endOperation(); workTask = nil }

        let box = AcceptedBox()
        let work = Task { @MainActor in
            box.value = await self.performSubmit(userText)
        }
        workTask = work
        await work.value
        return box.value
    }

    func confirmPendingPlan() async {
        guard beginOperation() else { return }
        defer { endOperation(); workTask = nil }

        let work = Task { @MainActor in
            await self.confirmPendingPlanUnlocked()
        }
        workTask = work
        await work.value
    }

    /// Explicit cancel only — hiding the agent window must not call this.
    func cancelPendingPlan() async {
        guard beginOperation() else { return }
        defer { endOperation() }
        _ = await performCancelPendingPlan()
    }

    func resetPhaseToIdle() {
        if case .completed = phase { phase = .idle }
        if case .failed = phase, activeTask?.pendingPlan == nil {
            phase = .idle
        }
    }

    /// Dismisses a failure. If a pending plan is still recoverable, abandons it
    /// (same retract path as Cancel) instead of returning to an unclean Run state.
    func dismissFailure() async {
        guard case .failed = phase else { return }
        if let plan = activeTask?.pendingPlan {
            guard beginOperation() else { return }
            defer { endOperation() }
            phase = .awaitingConfirmation(plan)
            _ = await performCancelPendingPlan()
            return
        }
        phase = .idle
    }

    // MARK: - Private

    private func beginOperation() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    private func endOperation() {
        isBusy = false
    }

    private func performRetry() async {
        if let plan = activeTask?.pendingPlan {
            phase = .awaitingConfirmation(plan)
            await confirmPendingPlanUnlocked()
            return
        }

        guard settings.isConfigured else {
            phase = .failed(message: ModelClientError.notConfigured.localizedDescription)
            return
        }
        guard !events.isEmpty else { return }

        let resumeWithoutTools = events.last?.kind == .toolResult
        phase = .thinking
        do {
            try Task.checkCancellation()
            let turn = try await requestModel(includeTools: !resumeWithoutTools)
            try Task.checkCancellation()
            await handleTurn(turn)
        } catch is CancellationError {
            await handleStop(plan: nil)
        } catch {
            await markFailed(error.localizedDescription)
        }
    }

    private func performSubmit(_ userText: String) async -> Bool {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard settings.isConfigured else {
            phase = .failed(message: ModelClientError.notConfigured.localizedDescription)
            return false
        }

        if activeTask?.pendingPlan != nil || hasPendingPlan {
            phase = .failed(
                message: "Finish, cancel, or retry the pending plan before sending a new request."
            )
            return false
        }

        if case .completed = phase { phase = .idle }
        if case .failed = phase { phase = .idle }

        if forceFreshOnNextSubmit {
            forceFreshOnNextSubmit = false
            contextHint = nil
            guard await beginNewTask(relatedTo: []) != nil else { return false }
        }

        let workspace = TaskWorkspaceSnapshot(
            activeTask: activeTask,
            recentSummaries: recentSummaries,
            activeTaskID: activeTaskID
        )
        let contextDecision = await contextResolver.resolve(
            input: trimmed,
            workspace: workspace
        )
        guard await apply(contextDecision) else { return false }
        guard await ensureActiveTask() else { return false }

        // Resumed task may carry a pending plan — refuse instead of wiping it.
        if let plan = activeTask?.pendingPlan {
            phase = .awaitingConfirmation(plan)
            return false
        }

        let userEvent = AgentEvent(
            kind: .userInput,
            content: trimmed,
            context: contextDecision.eventContext
        )
        guard await commit(
            appendEvents: [userEvent],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .active
                task.pendingPlan = nil
                if task.summary == nil {
                    task.summary = String(trimmed.prefix(160))
                }
                for relatedID in contextDecision.relatedTaskIDs
                    where relatedID != task.id && !task.relatedTaskIDs.contains(relatedID) {
                    task.relatedTaskIDs.append(relatedID)
                }
            }
        ) else { return false }

        if let hint = contextDecision.userVisibleHint {
            contextHint = hint
        }

        phase = .thinking
        lastAssistantText = nil

        do {
            try Task.checkCancellation()
            let turn = try await requestModel()
            try Task.checkCancellation()
            await handleTurn(turn)
        } catch is CancellationError {
            await handleStop(plan: nil)
        } catch {
            await markFailed(error.localizedDescription)
        }
        return true
    }

    private func confirmPendingPlanUnlocked() async {
        guard case .awaitingConfirmation(let initialPlan) = phase else { return }
        // Always normalize before Run/Retry so Dismiss→Run and relaunch can't skip
        // remaining steps or duplicate ERROR tool results.
        guard var plan = await preparePlanForResume(initialPlan) else { return }
        phase = .executing(plan)

        do {
            for index in plan.steps.indices {
                try Task.checkCancellation()

                if hasSuccessfulToolResult(for: plan.steps[index].toolCallID) {
                    plan.steps[index].status = .succeeded
                    continue
                }
                if plan.steps[index].status == .succeeded {
                    continue
                }

                plan.steps[index].status = .running
                phase = .executing(plan)

                guard await persistPlanState(plan) else {
                    await failDuringExecution(
                        plan: plan,
                        message: "Could not save progress. Retry to continue remaining steps."
                    )
                    return
                }

                let step = plan.steps[index]
                let resultEvent: AgentEvent
                do {
                    try Task.checkCancellation()
                    let result: String
                    if step.toolName.hasPrefix("mcp__"), let capabilities {
                        result = try await capabilities.callMCPTool(
                            qualifiedName: step.toolName,
                            argumentsJSON: step.argumentsJSON
                        )
                    } else if let tool = tools.tool(named: step.toolName) {
                        result = try await tool.call(argumentsJSON: step.argumentsJSON)
                    } else {
                        throw ToolError.operationFailed("Unknown tool: \(step.toolName)")
                    }
                    // Side effects may already have landed — persist before honoring Stop.
                    plan.steps[index].status = .succeeded
                    plan.steps[index].result = result
                    resultEvent = AgentEvent(
                        kind: .toolResult,
                        content: result,
                        toolCallID: step.toolCallID
                    )
                } catch is CancellationError {
                    plan.steps[index].status = .pending
                    throw CancellationError()
                } catch {
                    plan.steps[index].status = .failed
                    plan.steps[index].result = error.localizedDescription
                    resultEvent = AgentEvent(
                        kind: .toolResult,
                        content: "ERROR: \(error.localizedDescription)",
                        toolCallID: step.toolCallID
                    )

                    for later in (index + 1)..<plan.steps.count
                        where plan.steps[later].status != .succeeded {
                        plan.steps[later].status = .skipped
                    }

                    phase = .executing(plan)
                    guard await commit(
                        appendEvents: [resultEvent],
                        deleteEventIDs: [],
                        mutate: { task in
                            task.pendingPlan = plan
                            task.status = .awaitingApproval
                        }
                    ) else {
                        await failDuringExecution(
                            plan: plan,
                            message: "Could not save progress. Retry to continue remaining steps."
                        )
                        return
                    }
                    await failDuringExecution(
                        plan: plan,
                        message: "Step failed: \(error.localizedDescription)"
                    )
                    return
                }

                phase = .executing(plan)
                guard await commit(
                    appendEvents: [resultEvent],
                    deleteEventIDs: [],
                    mutate: { task in
                        task.pendingPlan = plan
                        task.status = .active
                    }
                ) else {
                    await failDuringExecution(
                        plan: plan,
                        message: "Could not save progress. Retry to continue remaining steps."
                    )
                    return
                }

                // Stop between steps only — never discard a committed success.
                try Task.checkCancellation()
            }

            guard await commit(
                appendEvents: [],
                deleteEventIDs: [],
                mutate: { task in
                    task.pendingPlan = nil
                }
            ) else {
                await failDuringExecution(
                    plan: plan,
                    message: "Could not save progress. Retry to continue remaining steps."
                )
                return
            }
            phase = .thinking

            try Task.checkCancellation()
            let turn = try await requestModel(includeTools: false)
            try Task.checkCancellation()
            let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text: String
            if let summary, !summary.isEmpty {
                text = summary
            } else {
                let fallback = plan.steps.compactMap(\.result).joined(separator: "\n")
                text = fallback.isEmpty ? "Done." : fallback
            }
            guard await commit(
                appendEvents: [AgentEvent(kind: .assistantResponse, content: text)],
                deleteEventIDs: [],
                mutate: { task in
                    task.status = .completed
                }
            ) else {
                phase = .failed(message: "Could not save the completion summary.")
                return
            }
            lastAssistantText = text
            phase = .completed(summary: text)
        } catch is CancellationError {
            await handleStop(plan: plan)
        } catch {
            await markFailed(error.localizedDescription)
        }
    }

    @discardableResult
    private func performCancelPendingPlan() async -> Bool {
        guard case .awaitingConfirmation = phase else { return false }

        let retractIDs = unexecutedToolProposalIDs(in: events)
        let text = "Cancelled. Nothing was changed."
        let cancelEvent = AgentEvent(kind: .assistantResponse, content: text)

        guard await commit(
            appendEvents: [cancelEvent],
            deleteEventIDs: retractIDs,
            mutate: { task in
                task.pendingPlan = nil
                task.status = .active
            }
        ) else { return false }

        lastAssistantText = text
        phase = .idle
        return true
    }

    private func handleStop(plan: AgentPlan?) async {
        if var plan {
            for index in plan.steps.indices where plan.steps[index].status == .running {
                plan.steps[index].status = .pending
            }
            await failDuringExecution(
                plan: plan,
                message: "Stopped. Retry to continue remaining steps."
            )
            return
        }

        // Keep a Retry path when work was already committed (user turn / tool results).
        switch events.last?.kind {
        case .toolResult:
            phase = .failed(message: "Stopped. Retry to summarize.")
        case .userInput:
            phase = .failed(message: "Stopped. Retry to continue.")
        default:
            phase = .idle
        }
    }

    /// Clears ERROR tool results and reopens failed/skipped steps before Run/Retry.
    private func preparePlanForResume(_ plan: AgentPlan) async -> AgentPlan? {
        var plan = plan
        let errorEventIDs = events.compactMap { event -> UUID? in
            guard event.kind == .toolResult,
                  event.content.hasPrefix("ERROR:")
            else { return nil }
            return event.id
        }

        for index in plan.steps.indices {
            if hasSuccessfulToolResult(for: plan.steps[index].toolCallID) {
                plan.steps[index].status = .succeeded
                continue
            }
            if plan.steps[index].status == .failed
                || plan.steps[index].status == .skipped
                || plan.steps[index].status == .running {
                plan.steps[index].status = .pending
                plan.steps[index].result = nil
            }
        }

        let ok = await commit(
            appendEvents: [],
            deleteEventIDs: errorEventIDs,
            mutate: { task in
                task.pendingPlan = plan
                task.status = .awaitingApproval
            }
        )
        guard ok else { return nil }
        return plan
    }

    private func handleTurn(_ turn: ModelTurn) async {
        if !turn.toolCalls.isEmpty {
            let summary = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "I can do this in \(turn.toolCalls.count) step\(turn.toolCalls.count == 1 ? "" : "s")."

            let storedCalls = turn.toolCalls.map {
                ToolCallRecord(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON)
            }
            let plan = AgentPlan(
                summary: summary,
                steps: turn.toolCalls.map { call in
                    AgentStep(
                        toolCallID: call.id,
                        toolName: call.name,
                        argumentsJSON: call.argumentsJSON,
                        title: humanTitle(for: call)
                    )
                }
            )
            guard await commit(
                appendEvents: [
                    AgentEvent(
                        kind: .assistantResponse,
                        content: summary,
                        toolCalls: storedCalls
                    ),
                ],
                deleteEventIDs: [],
                mutate: { task in
                    task.pendingPlan = plan
                    task.status = .awaitingApproval
                }
            ) else { return }

            phase = .awaitingConfirmation(plan)
            return
        }

        let text = turn.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reply = text.isEmpty ? "I couldn't produce a reply." : text
        guard await commit(
            appendEvents: [AgentEvent(kind: .assistantResponse, content: reply)],
            deleteEventIDs: [],
            mutate: { task in
                task.status = .completed
            }
        ) else { return }
        lastAssistantText = reply
        phase = .completed(summary: reply)
    }

    private func requestModel(includeTools: Bool = true) async throws -> ModelTurn {
        let snapshot = ModelSettingsSnapshot(
            baseURL: settings.baseURL,
            model: settings.model,
            apiKey: settings.apiKey
        )
        let skillsAppendix = capabilities?.skillsPromptAppendix() ?? ""
        let relatedAppendix = await relatedContextAppendix()
        var modelEvents = [
            AgentEvent(
                kind: .systemInstruction,
                content: systemPrompt + skillsAppendix + relatedAppendix
            )
        ]
        modelEvents.append(contentsOf: ContextBudget.select(from: events))

        let toolDefinitions: [ToolDefinition]
        if includeTools {
            toolDefinitions = tools.definitions + (capabilities?.mcpToolDefinitions() ?? [])
        } else {
            toolDefinitions = []
        }

        return try await modelClient.complete(
            events: modelEvents,
            tools: toolDefinitions,
            settings: snapshot
        )
    }

    private func relatedContextAppendix() async -> String {
        guard let task = activeTask else { return "" }
        let relatedIDs = Array(
            task.relatedTaskIDs
                .filter { $0 != task.id }
                .prefix(3)
        )
        guard !relatedIDs.isEmpty else { return "" }

        var lines = ["", "## Related prior work", "Use only if relevant to the current request:"]
        for id in relatedIDs {
            guard let related = try? await taskRepository.loadTask(id: id) else { continue }
            let title = related.summary?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("- \(title.flatMap { $0.isEmpty ? nil : $0 } ?? "Prior task")")
            if let lastUser = related.events.last(where: { $0.kind == .userInput })?.content {
                lines.append("  Last request: \(String(lastUser.prefix(220)))")
            }
            if let lastAssistant = related.events.last(where: {
                $0.kind == .assistantResponse && ($0.toolCalls?.isEmpty ?? true)
            })?.content {
                lines.append("  Last result: \(String(lastAssistant.prefix(220)))")
            }
        }
        return lines.count > 3 ? lines.joined(separator: "\n") : ""
    }

    @discardableResult
    private func ensureActiveTask() async -> Bool {
        if activeTaskID != nil, activeTask != nil { return true }
        return await createAndActivateTask(relatedTo: []) != nil
    }

    @discardableResult
    private func createAndActivateTask(relatedTo relatedTaskIDs: [UUID]) async -> UUID? {
        let task = TaskRecord(relatedTaskIDs: relatedTaskIDs)
        do {
            try await taskRepository.saveTaskState(task, setActive: true)
            activeTask = task
            activeTaskID = task.id
            refreshSummary(for: task)
            phase = .idle
            lastAssistantText = nil
            return task.id
        } catch {
            phase = .failed(message: "Could not create task storage: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func apply(_ decision: TaskContextDecision) async -> Bool {
        switch decision.action {
        case .continueActive:
            return true
        case .beginNew:
            contextHint = nil
            return await beginNewTask(relatedTo: decision.relatedTaskIDs) != nil
        case .resumeTask(let id):
            await activateTask(id)
            guard activeTaskID == id else { return false }
            if var task = activeTask {
                for relatedID in decision.relatedTaskIDs
                    where relatedID != task.id && !task.relatedTaskIDs.contains(relatedID) {
                    task.relatedTaskIDs.append(relatedID)
                }
                task.updatedAt = .now
                do {
                    try await taskRepository.saveTaskState(task, setActive: true)
                    activeTask = task
                    refreshSummary(for: task)
                } catch {
                    phase = .failed(message: "Could not update related context: \(error.localizedDescription)")
                    return false
                }
            }
            if let hint = decision.userVisibleHint {
                contextHint = hint
            } else if let task = activeTask {
                contextHint = Self.hint(for: task)
            }
            return true
        }
    }

    /// Updates memory only after a successful atomic DB mutation.
    @discardableResult
    private func commit(
        appendEvents: [AgentEvent],
        deleteEventIDs: [UUID],
        mutate: (inout TaskRecord) -> Void = { _ in }
    ) async -> Bool {
        guard var task = activeTask else { return false }
        mutate(&task)
        if !deleteEventIDs.isEmpty {
            let deleteSet = Set(deleteEventIDs)
            task.events.removeAll { deleteSet.contains($0.id) }
        }
        task.events.append(contentsOf: appendEvents)
        task.updatedAt = .now
        do {
            try await taskRepository.mutateTask(
                task,
                appendEvents: appendEvents,
                deleteEventIDs: deleteEventIDs,
                setActive: true
            )
            activeTask = task
            refreshSummary(for: task)
            return true
        } catch {
            phase = .failed(message: "Could not save task history: \(error.localizedDescription)")
            return false
        }
    }

    private func persistPlanState(_ plan: AgentPlan) async -> Bool {
        guard var task = activeTask else { return false }
        task.pendingPlan = plan
        task.status = .active
        task.updatedAt = .now
        do {
            try await taskRepository.saveTaskState(task, setActive: true)
            activeTask = task
            refreshSummary(for: task)
            return true
        } catch {
            return false
        }
    }

    private func failDuringExecution(plan: AgentPlan, message: String) async {
        if var task = activeTask {
            task.pendingPlan = plan
            task.status = .awaitingApproval
            task.updatedAt = .now
            activeTask = task
            try? await taskRepository.saveTaskState(task, setActive: true)
            refreshSummary(for: task)
        }
        phase = .failed(message: message)
    }

    private func markFailed(_ message: String) async {
        phase = .failed(message: message)
        guard var task = activeTask else { return }
        task.status = .failed
        task.updatedAt = .now
        do {
            try await taskRepository.saveTaskState(task, setActive: true)
            activeTask = task
            refreshSummary(for: task)
        } catch {
            activeTask = task
        }
    }

    private func refreshSummary(for task: TaskRecord) {
        let summary = TaskSummary(
            id: task.id,
            status: task.status,
            summary: task.summary,
            updatedAt: task.updatedAt
        )
        if let index = recentSummaries.firstIndex(where: { $0.id == task.id }) {
            recentSummaries[index] = summary
            recentSummaries.sort { $0.updatedAt > $1.updatedAt }
        } else {
            recentSummaries.insert(summary, at: 0)
        }
    }

    private func restorePhaseFromActiveTask() async {
        guard let task = activeTask else {
            phase = .idle
            lastAssistantText = nil
            return
        }
        lastAssistantText = task.events.last(where: {
            $0.kind == .assistantResponse && ($0.toolCalls?.isEmpty ?? true)
        })?.content
        if var plan = task.pendingPlan {
            for index in plan.steps.indices {
                if let result = task.events.last(where: {
                    $0.kind == .toolResult && $0.toolCallID == plan.steps[index].toolCallID
                }) {
                    if result.content.hasPrefix("ERROR:") {
                        plan.steps[index].status = .failed
                    } else {
                        plan.steps[index].status = .succeeded
                    }
                } else if plan.steps[index].status == .running {
                    plan.steps[index].status = .pending
                }
            }
            var updated = task
            let unfinished = plan.steps.contains {
                $0.status != .succeeded && $0.status != .skipped
            }
            if unfinished {
                updated.pendingPlan = plan
                activeTask = updated
                phase = .awaitingConfirmation(plan)
            } else {
                // All tools finished; clear persisted plan and offer summary retry.
                updated.pendingPlan = nil
                activeTask = updated
                try? await taskRepository.saveTaskState(updated, setActive: true)
                refreshSummary(for: updated)
                if updated.events.last?.kind == .toolResult {
                    phase = .failed(
                        message: "Interrupted after tools finished. Retry to summarize."
                    )
                } else {
                    phase = .idle
                }
            }
        } else {
            phase = .idle
        }
    }

    private func hasSuccessfulToolResult(for toolCallID: String) -> Bool {
        events.contains {
            $0.kind == .toolResult
                && $0.toolCallID == toolCallID
                && !$0.content.hasPrefix("ERROR:")
        }
    }

    private func unexecutedToolProposalIDs(in events: [AgentEvent]) -> [UUID] {
        let completed = Set(
            events.compactMap { event -> String? in
                guard event.kind == .toolResult else { return nil }
                return event.toolCallID
            }
        )
        return events.compactMap { event in
            guard event.kind == .assistantResponse,
                  let calls = event.toolCalls,
                  !calls.isEmpty,
                  !calls.contains(where: { completed.contains($0.id) })
            else { return nil }
            return event.id
        }
    }

    private func humanTitle(for call: ToolCallProposal) -> String {
        let args = (try? JSONDecoder().decode(
            [String: JSONValue].self,
            from: Data(call.argumentsJSON.utf8)
        )) ?? [:]
        switch call.name {
        case "list_directory":
            return "List \(args["path"]?.stringValue ?? "folder")"
        case "move_file":
            return "Move \(args["source"]?.stringValue ?? "file")"
        case "rename_file":
            return "Rename to \(args["new_name"]?.stringValue ?? "…")"
        case "create_directory":
            return "Create \(args["path"]?.stringValue ?? "folder")"
        case "read_text_file":
            return "Read \(args["path"]?.stringValue ?? "file")"
        case "write_text_file":
            return "Write \(args["path"]?.stringValue ?? "file")"
        case "get_clipboard":
            return "Read clipboard"
        case "set_clipboard":
            return "Update clipboard"
        case "open_application":
            return "Open \(args["name"]?.stringValue ?? "app")"
        case "open_url":
            return "Open URL"
        case "notify":
            return "Notify: \(args["title"]?.stringValue ?? "…")"
        default:
            return call.name
        }
    }

    private static func hint(for task: TaskRecord) -> String {
        if let summary = task.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            let clipped = summary.count > 48
                ? String(summary.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                : summary
            return "Using context from “\(clipped)”"
        }
        return "Using context from a related task"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Tiny box so `submit` can return a Bool from a cancellable `Task<Void, Never>`.
private final class AcceptedBox: @unchecked Sendable {
    var value = false
}
