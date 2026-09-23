//
//  ContextCompactor.swift
//  Sage
//
//  Background-first working-memory snapshots. Does not block the composer
//  unless lossless assembly still overflows.
//

import Foundation

/// Writes `TaskWorkingMemory` for the active task. Snapshots stay off the UI transcript.
@MainActor
final class ContextCompactor {
    /// Occupancy below which a finished snapshot is discarded (window grew / context shrank).
    nonisolated static let discardBelowOccupancy = 0.65
    /// First compact on a task waits longer (no prompt-cache warmth assumed).
    nonisolated static let coldStartThreshold = 0.90

    private let state: AgentSessionState
    private let taskStore: AgentTaskStore
    private let modelGateway: AgentModelGateway
    private let settings: ModelSettings
    /// Jittered warm threshold in 0.78...0.82, picked once per session.
    private let warmThreshold: Double
    private var compactedTaskIDs: Set<UUID> = []
    private var inFlight: Task<TaskWorkingMemory?, Never>?
    private var inFlightTaskID: UUID?

    init(
        state: AgentSessionState,
        taskStore: AgentTaskStore,
        modelGateway: AgentModelGateway,
        settings: ModelSettings
    ) {
        self.state = state
        self.taskStore = taskStore
        self.modelGateway = modelGateway
        self.settings = settings
        self.warmThreshold = 0.80 + Double.random(in: -0.02...0.02)
    }

    /// Cancels in-flight compact when the window leaves this task.
    func cancel() {
        inFlight?.cancel()
        inFlight = nil
        inFlightTaskID = nil
    }

    /// After a turn: fold if occupancy is high and a span exists.
    func considerBackground(
        occupancy: Double,
        tools: [ToolDefinition]
    ) {
        guard inFlight == nil else { return }
        guard let taskID = state.activeTaskID else { return }
        guard occupancy >= threshold(for: taskID) else { return }
        startJob(taskID: taskID, tools: tools)
    }

    /// Foreground path when lossless assembly still overflowed or occupancy
    /// crossed the auto-compact threshold. Reuses an in-flight job when one exists.
    @discardableResult
    func handleOverflow(tools: [ToolDefinition]) async -> TaskWorkingMemory? {
        if let inFlight {
            return await inFlight.value
        }
        guard let taskID = state.activeTaskID else { return nil }
        startJob(taskID: taskID, tools: tools)
        return await inFlight?.value
    }

    // MARK: - Internals

    private func threshold(for taskID: UUID) -> Double {
        compactedTaskIDs.contains(taskID) ? warmThreshold : Self.coldStartThreshold
    }

    private func startJob(taskID: UUID, tools: [ToolDefinition]) {
        let events = state.events
        let existing = state.activeTask?.workingMemory
        guard ConversationFold.span(in: events, existing: existing) != nil else { return }

        let snapshot = settings.snapshot(for: .execute)
        inFlightTaskID = taskID
        inFlight = Task { [weak self] in
            guard let self else { return nil }
            let result = await self.buildSnapshot(
                taskID: taskID,
                events: events,
                existing: existing,
                settings: snapshot,
                tools: tools
            )
            await self.finish(result, for: taskID)
            if case .memory(let memory) = result {
                return memory
            }
            return nil
        }
    }

    private func finish(_ result: CompactBuildResult, for taskID: UUID) async {
        if inFlightTaskID == taskID {
            inFlight = nil
            inFlightTaskID = nil
        }
        guard state.activeTaskID == taskID else { return }
        switch result {
        case .skipped:
            return

        case .failed(let reason):
            state.compactNotice = CompactTask.Outcome.failed(reason).notice

        case .memory(let memory):
            guard memory.hasContent else { return }
            let occupancy = await modelGateway.occupancyIgnoringWorkingMemory()
            guard Self.shouldKeepSnapshot(occupancyIgnoringMemory: occupancy) else { return }
            if await taskStore.applyWorkingMemory(memory, to: taskID) {
                compactedTaskIDs.insert(taskID)
                state.compactNotice = nil
            } else {
                state.compactNotice = CompactTask.Outcome.failed(
                    "could not save the working-memory snapshot"
                ).notice
            }
        }
    }

    /// Keep a finished snapshot only when raw history still crowds the window.
    nonisolated static func shouldKeepSnapshot(occupancyIgnoringMemory: Double) -> Bool {
        occupancyIgnoringMemory >= discardBelowOccupancy
    }

    private func buildSnapshot(
        taskID: UUID,
        events: [AgentEvent],
        existing: TaskWorkingMemory?,
        settings: ModelSettingsSnapshot,
        tools: [ToolDefinition]
    ) async -> CompactBuildResult {
        do {
            try Task.checkCancellation()
            guard let span = ConversationFold.span(in: events, existing: existing) else {
                return .skipped
            }
            var compactEvents: [AgentEvent] = []
            if let existing, existing.hasContent {
                compactEvents.append(
                    AgentEvent(kind: .systemInstruction, content: existing.promptAppendix)
                )
            }
            let slice = ConversationFold.slice(
                events,
                from: span.fromEventID,
                through: span.throughEventID
            )
            let budget = PromptBudget.forModel(settings.model)
            let spanBudget = PromptBudget(
                windowTokens: max(budget.windowTokens / 3, 4_000),
                reservedOutputTokens: 512,
                reservedToolTokens: 0
            )
            compactEvents.append(
                contentsOf: CompactTask.selectFoldSlice(slice, budget: spanBudget)
            )
            compactEvents.append(
                AgentEvent(kind: .userInput, content: CompactTask.compactInstruction)
            )

            let compactTools = tools.filter { $0.name != RecallTaskTranscriptTool.name }
            let raw = try await modelGateway.completeForCompaction(
                events: compactEvents,
                tools: compactTools
            )
            try Task.checkCancellation()
            guard state.activeTaskID == taskID else { return .skipped }

            guard let memory = WorkingMemoryParser.parse(
                raw,
                foldedFromEventID: existing?.foldedFromEventID ?? span.fromEventID,
                foldedThroughEventID: span.throughEventID,
                sourceModel: settings.model
            ), memory.hasContent else {
                return .failed("the compressor returned an empty snapshot")
            }
            return .memory(memory)
        } catch is CancellationError {
            return .skipped
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static let compactInstruction = CompactTask.compactInstruction
}

private enum CompactBuildResult {
    case memory(TaskWorkingMemory)
    case skipped
    case failed(String)
}
