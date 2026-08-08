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
    /// Incrementally accumulated text during streaming. Empty when not streaming.
    private(set) var streamingText: String = ""
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

    /// True when the model is actively streaming text (first token has arrived).
    var isStreaming: Bool {
        if case .thinking = phase { return !streamingText.isEmpty }
        return false
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
    private let taskRouter: TaskRouter
    private let topicGenerator: TopicGenerator
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
        taskRouter: TaskRouter = TaskRouter(),
        topicGenerator: TopicGenerator = TopicGenerator(),
        capabilities: CapabilityStore? = nil
    ) {
        self.settings = settings
        self.tools = tools
        self.taskRepository = taskRepository
        self.contextResolver = contextResolver
        self.taskRouter = taskRouter
        self.topicGenerator = topicGenerator
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

        // Warm up the local model in the background — non-blocking.
        Task.detached(priority: .utility) {
            await LocalModelService.shared.warmUp()
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
        var inheritedRelated = relatedTaskIDs
        // Persist the closed prior task before switching memory.
        if var closing = activeTask {
            let retractIDs = unexecutedToolProposalIDs(in: closing.events)
            if !retractIDs.isEmpty {
                let deleteSet = Set(retractIDs)
                closing.events.removeAll { deleteSet.contains($0.id) }
            }

            do {
                if closing.events.isEmpty {
                    // Empty shells must not linger as completed catalog noise.
                    try await taskRepository.deleteTask(id: closing.id)
                    recentSummaries.removeAll { $0.id == closing.id }
                } else {
                    if closing.status == .active || closing.status == .awaitingApproval {
                        closing.status = .completed
                    }
                    closing.pendingPlan = nil
                    closing.updatedAt = .now
                    try await taskRepository.mutateTask(
                        closing,
                        appendEvents: [],
                        deleteEventIDs: retractIDs,
                        setActive: false
                    )
                    refreshSummary(for: closing)
                    // Closing via route/start-fresh often skips the .completed phase —
                    // still generate a topic so the task can re-enter the catalog.
                    scheduleTopicGeneration(for: closing)
                    // Link the closed task so related-context injection can fire.
                    if !inheritedRelated.contains(closing.id) {
                        inheritedRelated.insert(closing.id, at: 0)
                    }
                }
                phase = .idle
                lastAssistantText = nil
            } catch {
                phase = .failed(message: "Could not close the previous task: \(error.localizedDescription)")
                return nil
            }
        }

        // Clear stale references before creating the new task so that a failure
        // in createAndActivateTask never leaves the runtime pointing at a
        // completed/closed task.
        activeTask = nil
        activeTaskID = nil

        return await createAndActivateTask(
            relatedTo: Array(inheritedRelated.prefix(Self.maxRelatedTaskIDs))
        )
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
        workTask?.cancel()
        workTask = nil
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
        streamingText = ""
        do {
            try Task.checkCancellation()
            let turn = try await requestModelStreaming(includeTools: !resumeWithoutTools)
            try Task.checkCancellation()
            await handleTurn(turn)
        } catch is CancellationError {
            streamingText = ""
            await handleStop(plan: nil)
        } catch {
            streamingText = ""
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

        // Dismiss-chip / force-fresh must not be undone by resume routing.
        let forcedFresh: Bool
        if forceFreshOnNextSubmit {
            forceFreshOnNextSubmit = false
            contextHint = nil
            guard await beginNewTask(relatedTo: []) != nil else { return false }
            forcedFresh = true
        } else {
            forcedFresh = false
        }

        let effectiveDecision: TaskContextDecision
        if forcedFresh {
            effectiveDecision = TaskContextDecision(
                action: .continueActive,
                relatedTaskIDs: [],
                confidence: 1,
                reason: "User forced a fresh task boundary",
                userVisibleHint: nil
            )
        } else {
            let workspace = TaskWorkspaceSnapshot(
                activeTask: activeTask,
                recentSummaries: recentSummaries,
                activeTaskID: activeTaskID
            )
            let contextDecision = await contextResolver.resolve(
                input: trimmed,
                workspace: workspace
            )

            // Local model routing: refine when the heuristic says "continue"
            // (topic drift → new, or resume a prior catalogued task).
            if case .continueActive = contextDecision.action {
                if let routingResult = await applyLocalRouting(input: trimmed) {
                    guard let routed = await applyRoutingDecision(
                        routingResult,
                        input: trimmed
                    ) else { return false }
                    effectiveDecision = routed
                } else {
                    effectiveDecision = contextDecision
                }
            } else {
                guard let applied = await apply(contextDecision) else { return false }
                effectiveDecision = applied
            }
        }

        guard await ensureActiveTask() else { return false }

        // Defensive: resume paths refuse tasks with a pending plan, but keep
        // this guard so we never wipe a plan if state races.
        if let plan = activeTask?.pendingPlan {
            phase = .awaitingConfirmation(plan)
            return false
        }

        let userEvent = AgentEvent(
            kind: .userInput,
            content: trimmed,
            context: effectiveDecision.eventContext
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
                for relatedID in effectiveDecision.relatedTaskIDs
                    where relatedID != task.id && !task.relatedTaskIDs.contains(relatedID) {
                    task.relatedTaskIDs.append(relatedID)
                }
            }
        ) else { return false }

        if let hint = effectiveDecision.userVisibleHint {
            contextHint = hint
        }

        phase = .thinking
        lastAssistantText = nil
        streamingText = ""

        do {
            try Task.checkCancellation()
            let turn = try await requestModelStreaming()
            try Task.checkCancellation()
            await handleTurn(turn)
        } catch is CancellationError {
            streamingText = ""
            await handleStop(plan: nil)
        } catch {
            streamingText = ""
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
                    let rawResult: String
                    if step.toolName.hasPrefix("mcp__"), let capabilities {
                        rawResult = try await capabilities.callMCPTool(
                            qualifiedName: step.toolName,
                            argumentsJSON: step.argumentsJSON
                        )
                    } else if let tool = tools.tool(named: step.toolName) {
                        // Some tools manage their own timeout or may involve user interaction
                        // (permission prompts, interactive capture). Give them extended ceilings.
                        let interactiveTools: Set<String> = [
                            "run_shell_command",   // manages its own 120s timeout
                            "take_screenshot",     // may trigger Screen Recording permission prompt
                            "toggle_appearance",   // may trigger System Events permission prompt
                            "create_reminder",     // may trigger Reminders permission prompt
                        ]
                        let timeout: Duration = interactiveTools.contains(step.toolName)
                            ? .seconds(130)
                            : toolExecutionTimeout
                        rawResult = try await withThrowingTaskGroup(of: String.self) { group in
                            group.addTask {
                                try await tool.call(argumentsJSON: step.argumentsJSON)
                            }
                            group.addTask {
                                try await Task.sleep(for: timeout)
                                throw ToolError.operationFailed(
                                    "Tool '\(step.toolName)' timed out after \(Int(timeout.components.seconds))s"
                                )
                            }
                            let result = try await group.next()!
                            group.cancelAll()
                            return result
                        }
                    } else {
                        throw ToolError.operationFailed("Unknown tool: \(step.toolName)")
                    }
                    let result = capToolResult(rawResult)
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
            streamingText = ""

            try Task.checkCancellation()
            let turn = try await requestModelStreaming(includeTools: false)
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
                streamingText = ""
                phase = .failed(message: "Could not save the completion summary.")
                return
            }
            streamingText = ""
            lastAssistantText = text
            phase = .completed(summary: text)
            generateTopicIfNeeded()
        } catch is CancellationError {
            streamingText = ""
            await handleStop(plan: plan)
        } catch {
            streamingText = ""
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

            streamingText = ""
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
        // Clear streaming state AFTER the event is committed — the committed event bubble
        // is now in the transcript, so clearing streamingText won't cause a visual flash.
        streamingText = ""
        lastAssistantText = reply
        phase = .completed(summary: reply)
        generateTopicIfNeeded()
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

    /// Streaming variant of `requestModel` — incrementally updates `streamingText`
    /// and returns the assembled `ModelTurn` when the stream finishes.
    private func requestModelStreaming(includeTools: Bool = true) async throws -> ModelTurn {
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

        let stream = try await modelClient.streamComplete(
            events: modelEvents,
            tools: toolDefinitions,
            settings: snapshot
        )

        // Accumulate deltas into the final turn
        var contentBuffer = ""
        // Tool call accumulators keyed by index
        var toolCallBuilders: [Int: ToolCallBuilder] = [:]

        streamingText = ""

        for try await delta in stream {
            try Task.checkCancellation()

            switch delta {
            case .text(let chunk):
                contentBuffer += chunk
                streamingText = contentBuffer

            case .toolCallDelta(let index, let id, let name, let arguments):
                var builder = toolCallBuilders[index] ?? ToolCallBuilder()
                if let id { builder.id = id }
                if let name { builder.name = name }
                if let arguments { builder.arguments += arguments }
                toolCallBuilders[index] = builder

            case .done:
                break
            }
        }

        // Note: streamingText is intentionally NOT cleared here.
        // handleTurn will commit the text as an event, then clear streamingText,
        // ensuring no visual flash between streaming content and the committed bubble.

        // Assemble tool calls from builders, sorted by index
        let toolCalls = toolCallBuilders.keys.sorted().compactMap { index -> ToolCallProposal? in
            guard let builder = toolCallBuilders[index],
                  let id = builder.id,
                  let name = builder.name
            else { return nil }
            return ToolCallProposal(id: id, name: name, argumentsJSON: builder.arguments)
        }

        let content = contentBuffer.isEmpty ? nil : contentBuffer
        return ModelTurn(content: content, toolCalls: toolCalls)
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
            let topic = related.topic?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let summary = related.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let title = topic ?? summary ?? "Prior task"
            lines.append("- \(title)")
            if let abstract = related.abstract?.trimmingCharacters(in: .whitespacesAndNewlines),
               !abstract.isEmpty {
                lines.append("  Intent: \(abstract)")
            }
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

    private static let maxRelatedTaskIDs = 8

    /// Applies a heuristic context decision. Returns the effective decision
    /// (may downgrade a blocked resume to continue), or nil on hard failure.
    private func apply(_ decision: TaskContextDecision) async -> TaskContextDecision? {
        switch decision.action {
        case .continueActive:
            return decision
        case .beginNew:
            contextHint = nil
            guard await beginNewTask(relatedTo: decision.relatedTaskIDs) != nil else {
                return nil
            }
            return decision
        case .resumeTask(let id):
            return await resumeTask(
                id,
                extraRelatedIDs: decision.relatedTaskIDs,
                inputForTopicUpdate: nil,
                confidence: decision.confidence,
                reason: decision.reason,
                userVisibleHint: decision.userVisibleHint
            )
        }
    }

    /// Shared resume path for heuristic + local-model routing.
    private func resumeTask(
        _ id: UUID,
        extraRelatedIDs: [UUID],
        inputForTopicUpdate: String?,
        confidence: Double,
        reason: String,
        userVisibleHint: String?
    ) async -> TaskContextDecision? {
        if await taskHasPendingPlan(id) {
            return TaskContextDecision(
                action: .continueActive,
                relatedTaskIDs: [],
                confidence: confidence,
                reason: "Resume skipped: target has pending plan",
                userVisibleHint: nil
            )
        }

        let previousID = activeTaskID
        await activateTask(id)
        guard activeTaskID == id else { return nil }

        if var task = activeTask {
            var changed = false
            if let previousID,
               previousID != task.id,
               !task.relatedTaskIDs.contains(previousID) {
                task.relatedTaskIDs.insert(previousID, at: 0)
                changed = true
            }
            for relatedID in extraRelatedIDs
                where relatedID != task.id && !task.relatedTaskIDs.contains(relatedID) {
                task.relatedTaskIDs.append(relatedID)
                changed = true
            }
            if task.relatedTaskIDs.count > Self.maxRelatedTaskIDs {
                task.relatedTaskIDs = Array(task.relatedTaskIDs.prefix(Self.maxRelatedTaskIDs))
                changed = true
            }
            if changed {
                task.updatedAt = .now
                do {
                    try await taskRepository.saveTaskState(task, setActive: true)
                    adoptTaskInMemory(task)
                } catch {
                    phase = .failed(message: "Could not update related context: \(error.localizedDescription)")
                    return nil
                }
            }

            if let inputForTopicUpdate,
               let existingTopic = task.topic,
               let existingAbstract = task.abstract {
                let targetID = id
                Task.detached(priority: .utility) { [topicGenerator] in
                    if let updated = await topicGenerator.update(
                        existingTopic: existingTopic,
                        existingAbstract: existingAbstract,
                        newInput: inputForTopicUpdate
                    ) {
                        await MainActor.run { [weak self] in
                            self?.updateTaskTopic(updated, for: targetID)
                        }
                    }
                }
            }
        }

        let hint = userVisibleHint ?? activeTask.map(Self.hint(for:))
        if let hint { contextHint = hint }
        return TaskContextDecision(
            action: .resumeTask(id),
            relatedTaskIDs: [],
            confidence: confidence,
            reason: reason,
            userVisibleHint: hint
        )
    }

    private func taskHasPendingPlan(_ id: UUID) async -> Bool {
        if activeTaskID == id { return activeTask?.pendingPlan != nil }
        return (try? await taskRepository.hasPendingPlan(taskID: id)) ?? false
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
            adoptTaskInMemory(task)
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
            adoptTaskInMemory(task)
            return true
        } catch {
            return false
        }
    }

    /// Writes `task` into memory, preserving a topic that arrived concurrently
    /// (topic generation finishing while commit/plan save was in flight).
    private func adoptTaskInMemory(_ task: TaskRecord) {
        var merged = task
        if merged.topic == nil,
           let current = activeTask,
           current.id == merged.id,
           let topic = current.topic {
            merged.topic = topic
            merged.abstract = current.abstract
            merged.topicUpdatedAt = current.topicUpdatedAt
        }
        activeTask = merged
        refreshSummary(for: merged)
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
            topic: task.topic,
            abstract: task.abstract,
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
        case "search_files":
            return "Search \(args["path"]?.stringValue ?? "files")"
        case "read_text_file":
            return "Read \(args["path"]?.stringValue ?? "file")"
        case "write_text_file":
            return "Write \(args["path"]?.stringValue ?? "file")"
        case "copy_file":
            return "Copy \(args["source"]?.stringValue ?? "file")"
        case "delete_file":
            return "Delete \(args["path"]?.stringValue ?? "file")"
        case "run_shell_command":
            let cmd = args["command"]?.stringValue ?? "command"
            let short = cmd.count > 30 ? String(cmd.prefix(27)) + "…" : cmd
            return "Run: \(short)"
        case "get_clipboard":
            return "Read clipboard"
        case "set_clipboard":
            return "Update clipboard"
        case "get_selected_text":
            return "Get selection"
        case "type_text":
            let text = args["text"]?.stringValue ?? ""
            let preview = text.count > 20 ? String(text.prefix(17)) + "…" : text
            return "Type: \(preview)"
        case "get_screen_info":
            return "Get screen info"
        case "get_frontmost_app":
            return "Check active app"
        case "open_application":
            return "Open \(args["name"]?.stringValue ?? "app")"
        case "open_url":
            return "Open URL"
        case "notify":
            return "Notify: \(args["title"]?.stringValue ?? "…")"
        case "get_system_volume":
            return "Get volume"
        case "set_system_volume":
            return "Set volume to \(args["volume"]?.stringValue ?? "…")%"
        case "toggle_appearance":
            return "Toggle appearance"
        case "create_reminder":
            let title = args["title"]?.stringValue ?? "reminder"
            let short = title.count > 20 ? String(title.prefix(17)) + "…" : title
            return "Remind: \(short)"
        case "take_screenshot":
            return "Take screenshot"
        default:
            return call.name
        }
    }

    private static func hint(for task: TaskRecord) -> String {
        if let topic = task.topic?.trimmingCharacters(in: .whitespacesAndNewlines),
           !topic.isEmpty {
            return "Using context from \u{201C}\(topic)\u{201D}"
        }
        if let summary = task.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            let clipped = summary.count > 48
                ? String(summary.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                : summary
            return "Using context from \u{201C}\(clipped)\u{201D}"
        }
        return "Using context from a related task"
    }

    // MARK: - Local Model Routing

    /// Asks the local model to route the input. Returns nil if the model decides
    /// (or falls back to) continuing the current task.
    private func applyLocalRouting(input: String) async -> TaskRoutingDecision? {
        let catalog = TaskCatalog.build(
            from: recentSummaries,
            excluding: activeTaskID
        )
        let activeIsEmpty = activeTask?.events.isEmpty ?? true
        // Skip only when there is neither a conversation to leave nor a catalog
        // to resume. A non-empty active task with an empty catalog still needs
        // routing so the model can emit `new` on topic drift.
        if catalog.entries.isEmpty && activeIsEmpty {
            return heuristicRoutingDecision(input: input)
        }

        let decision = await taskRouter.route(
            input: input,
            currentTopic: activeTask?.topic ?? activeTask?.summary.map {
                String($0.prefix(20))
            },
            catalog: catalog
        )

        switch decision.action {
        case .continueActive:
            // Low confidence = model unavailable / unparseable — try lexical fallback.
            if decision.confidence <= 0.5 {
                return heuristicRoutingDecision(input: input)
            }
            return nil
        case .resumeTask, .beginNew:
            return decision
        }
    }

    private func heuristicRoutingDecision(input: String) -> TaskRoutingDecision? {
        let workspace = TaskWorkspaceSnapshot(
            activeTask: activeTask,
            recentSummaries: recentSummaries,
            activeTaskID: activeTaskID
        )
        guard let decision = HeuristicTaskFallback.decide(
            input: input,
            workspace: workspace
        ) else {
            return nil
        }
        switch decision.action {
        case .continueActive:
            return nil
        case .beginNew:
            return TaskRoutingDecision(
                action: .beginNew,
                confidence: decision.confidence,
                reason: decision.reason
            )
        case .resumeTask(let id):
            return TaskRoutingDecision(
                action: .resumeTask(id),
                confidence: decision.confidence,
                reason: decision.reason
            )
        }
    }

    /// Applies a local model routing decision. Returns the effective context
    /// decision for event metadata, or nil on hard failure.
    private func applyRoutingDecision(
        _ decision: TaskRoutingDecision,
        input: String
    ) async -> TaskContextDecision? {
        switch decision.action {
        case .continueActive:
            return TaskContextDecision(
                action: .continueActive,
                relatedTaskIDs: activeTask?.relatedTaskIDs ?? [],
                confidence: decision.confidence,
                reason: decision.reason,
                userVisibleHint: nil
            )
        case .beginNew:
            contextHint = nil
            guard await beginNewTask(relatedTo: []) != nil else { return nil }
            return TaskContextDecision(
                action: .beginNew,
                relatedTaskIDs: [],
                confidence: decision.confidence,
                reason: decision.reason,
                userVisibleHint: nil
            )
        case .resumeTask(let id):
            return await resumeTask(
                id,
                extraRelatedIDs: [],
                inputForTopicUpdate: input,
                confidence: decision.confidence,
                reason: decision.reason,
                userVisibleHint: nil
            )
        }
    }

    /// Updates a task's topic/abstract in memory (if still active) and persists
    /// via a topic-only write so concurrent plan/event saves cannot be clobbered.
    private func updateTaskTopic(_ result: TopicResult, for taskID: UUID? = nil) {
        let targetID = taskID ?? activeTask?.id
        guard let targetID else { return }
        let stampedAt = Date.now

        if var task = activeTask, task.id == targetID {
            task.topic = result.topic
            task.abstract = result.abstract
            task.topicUpdatedAt = stampedAt
            task.updatedAt = stampedAt
            activeTask = task
            refreshSummary(for: task)
        } else if let index = recentSummaries.firstIndex(where: { $0.id == targetID }) {
            recentSummaries[index] = TaskSummary(
                id: recentSummaries[index].id,
                status: recentSummaries[index].status,
                summary: recentSummaries[index].summary,
                topic: result.topic,
                abstract: result.abstract,
                updatedAt: stampedAt
            )
            recentSummaries.sort { $0.updatedAt > $1.updatedAt }
        }

        Task {
            try? await taskRepository.updateTopic(
                taskID: targetID,
                topic: result.topic,
                abstract: result.abstract,
                topicUpdatedAt: stampedAt
            )
        }
    }

    // MARK: - Topic Generation on Completion

    /// Tasks currently undergoing topic generation — prevents duplicate runs.
    private var topicGenerationTaskIDs: Set<UUID> = []

    /// Called after a task completes to generate its topic if missing.
    func generateTopicIfNeeded() {
        guard let task = activeTask else { return }
        scheduleTopicGeneration(for: task)
    }

    /// Schedules topic generation for any task (active or just closed).
    private func scheduleTopicGeneration(for task: TaskRecord) {
        guard task.topic == nil, !task.events.isEmpty else { return }
        guard !topicGenerationTaskIDs.contains(task.id) else { return }
        topicGenerationTaskIDs.insert(task.id)

        let taskID = task.id
        let events = task.events
        Task.detached(priority: .utility) { [topicGenerator, weak self] in
            let result = await topicGenerator.generate(from: events)
            await MainActor.run { [weak self] in
                self?.topicGenerationTaskIDs.remove(taskID)
                if let result {
                    self?.updateTaskTopic(result, for: taskID)
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Accumulates streamed tool call fragments into a complete proposal.
private struct ToolCallBuilder {
    var id: String?
    var name: String?
    var arguments: String = ""
}

/// Tiny box so `submit` can return a Bool from a cancellable `Task<Void, Never>`.
private final class AcceptedBox: @unchecked Sendable {
    var value = false
}
