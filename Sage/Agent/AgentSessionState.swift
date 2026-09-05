//
//  AgentSessionState.swift
//  Sage
//
//  Observable session fields. Task identity is switched through AgentTaskStore;
//  phase through the enter*/fail/complete methods below; busy through
//  SessionOperationGate.
//

import Foundation

@MainActor
@Observable
final class AgentSessionState {
    /// Full active task only — other tasks stay as lightweight summaries.
    var activeTask: TaskRecord?
    var recentSummaries: [TaskSummary] = []
    var activeTaskID: UUID?
    /// Focused code project (`nil` = General).
    var focusedProject: ProjectRecord?
    var recentProjects: [ProjectRecord] = []
    private(set) var phase: AgentPhase = .idle
    var lastAssistantText: String?
    /// Retry countdown — non-nil while waiting to retry a transient error.
    var retryState: RetryDisplayState?
    /// Cumulative token usage for the current task (cleared on beginNewTask).
    var tokenUsage = TokenUsage()
    /// Soft chip when Sage resumes related prior work (not ordinary continuity).
    var contextHint: String?
    /// Non-blocking offer to peel the latest turn into a new task.
    var topicDriftOffer: TopicDriftOffer?
    /// After “Keep Going”, don’t re-offer on this task until a new thread starts.
    var suppressedDriftOfferTaskID: UUID?
    /// True while peeling the latest turn into a new task (blocks double-taps).
    var isAcceptingTopicDrift = false
    private(set) var isBusy = false
    /// Confirm-card buttons disable while composer submit is in flight or the
    /// queue/redirect dialog is up. `isBusy` follows once the turn gate opens.
    private(set) var confirmationActionsFrozen = false
    /// After dismissing the context chip, the next submit starts a clean task.
    var forceFreshOnNextSubmit = false
    /// True while Review is inspecting the current world off-transcript.
    var isReviewing = false
    /// Reviewer notes for the next execute pass. Cleared on accept / new submit.
    var reviewFeedback: String?
    /// Mid-turn redirect from the user. Distinct from review feedback.
    var steerInstruction: String?
    /// Skills already loaded via `load_skill` / slash activation in this task.
    var activatedSkillNames: Set<String> = []
    /// Set when the owning window is closing — blocks further DB commits.
    var isTornDown = false
    /// Becomes true after the first `bootstrap` finishes (success or failure).
    /// UI must not paint workspace chrome/transcript until this is set.
    var didBootstrap = false
    /// Exact shell / MCP invocations approved for the current task.
    let sessionAllowlist = SessionToolAllowlist()
    /// Attachment-bearing events retained in the most recently assembled model context.
    var modelVisibleAttachmentEventIDs: Set<UUID> = []
    /// Round-limit or per-tool approval sitting in front of the execute loop.
    var pendingPrompt: AgentPendingPrompt?
    /// Net file mutations for the current execute→review cycle.
    let workspaceChanges = TurnChangeSet()
    /// Mid-turn user messages: offer, queue, and in-flight steer.
    let turnInput = TurnInputQueue()
    /// Queues parked when this window leaves a thread. Lost on quit.
    var parkedTurnInput: [UUID: TurnInputQueue.Snapshot] = [:]

    func parkTurnInput(for taskID: UUID) {
        let snapshot = turnInput.snapshot
        turnInput.reset()
        if snapshot.isEmpty {
            parkedTurnInput.removeValue(forKey: taskID)
        } else {
            parkedTurnInput[taskID] = snapshot
        }
    }

    func restoreTurnInput(for taskID: UUID) {
        if let snapshot = parkedTurnInput.removeValue(forKey: taskID) {
            turnInput.apply(snapshot)
        } else {
            turnInput.reset()
        }
    }

    func discardParkedTurnInput(for taskID: UUID) {
        parkedTurnInput.removeValue(forKey: taskID)
        turnInput.reset()
    }

    func clearParkedTurnInput() {
        parkedTurnInput = [:]
        turnInput.reset()
    }

    var events: [AgentEvent] {
        activeTask?.events ?? []
    }

    var hasPendingPlan: Bool {
        if case .awaitingConfirmation = phase { return true }
        return activeTask?.pendingPlan != nil || pendingPrompt != nil
    }

    func clearPendingPrompt() {
        pendingPrompt = nil
    }

    var pathGuardPolicy: PathGuard.Policy {
        if let focusedProject {
            return .project(root: focusedProject.rootURL)
        }
        return .home
    }

    /// Scheduled runs share grants across their ephemeral task records.
    var authorizationScopeID: String {
        if let scheduleID = activeTask?.originScheduleID {
            return "schedule:\(scheduleID.uuidString)"
        }
        return "task:\(activeTaskID?.uuidString ?? "unbound")"
    }

    var focusTitle: String {
        focusedProject?.name ?? "General"
    }

    /// Short label for the current thread (chrome wayfinding).
    var threadTitle: String? {
        guard let label = TopicDriftDetector.threadLabel(
            topic: activeTask?.topic,
            abstract: activeTask?.abstract,
            summary: activeTask?.summary
        ) else { return nil }
        if activeTask?.originScheduleID != nil {
            return "Scheduled · \(label)"
        }
        return label
    }

    func clearTopicDriftOffer() {
        topicDriftOffer = nil
    }

    func dismissTopicDriftOffer() {
        if let taskID = topicDriftOffer?.taskID {
            suppressedDriftOfferTaskID = taskID
        }
        topicDriftOffer = nil
    }

    func clearThreadRoutingNotices() {
        topicDriftOffer = nil
        suppressedDriftOfferTaskID = nil
        contextHint = nil
        forceFreshOnNextSubmit = false
        isReviewing = false
        reviewFeedback = nil
        steerInstruction = nil
        pendingPrompt = nil
        workspaceChanges.reset()
    }

    func clearTokenUsage() {
        tokenUsage = TokenUsage()
    }

    func addTokenUsage(_ usage: TokenUsage) {
        guard usage.input > 0 || usage.output > 0 else { return }
        tokenUsage.input += usage.input
        tokenUsage.output += usage.output
    }

    func refreshSummary(for task: TaskRecord) {
        guard task.projectID == focusedProject?.id else { return }
        if task.originScheduleID != nil {
            recentSummaries.removeAll { $0.id == task.id }
            return
        }
        let summary = TaskSummary(
            id: task.id,
            status: task.status,
            projectID: task.projectID,
            summary: task.summary,
            topic: task.topic,
            abstract: task.abstract,
            updatedAt: task.updatedAt,
            originScheduleID: task.originScheduleID
        )
        if let index = recentSummaries.firstIndex(where: { $0.id == task.id }) {
            recentSummaries[index] = summary
        } else {
            recentSummaries.insert(summary, at: 0)
        }
        recentSummaries = TaskSummary.sortedForRecents(recentSummaries)
    }

    func removeSummary(id: UUID) {
        recentSummaries.removeAll { $0.id == id }
    }

    func adoptActiveTaskTopic(_ result: TopicResult, stampedAt: Date) {
        guard var task = activeTask else { return }
        task.topic = result.topic
        task.abstract = result.abstract
        task.topicUpdatedAt = stampedAt
        task.updatedAt = stampedAt
        activeTask = task
        refreshSummary(for: task)
    }

    func updateRecentSummaryTopic(taskID: UUID, result: TopicResult, stampedAt: Date) {
        guard let index = recentSummaries.firstIndex(where: { $0.id == taskID }) else { return }
        let prior = recentSummaries[index]
        if prior.originScheduleID != nil {
            recentSummaries.remove(at: index)
            return
        }
        recentSummaries[index] = TaskSummary(
            id: prior.id,
            status: prior.status,
            projectID: prior.projectID,
            summary: prior.summary,
            topic: result.topic,
            abstract: result.abstract,
            updatedAt: stampedAt,
            originScheduleID: prior.originScheduleID
        )
        recentSummaries = TaskSummary.sortedForRecents(recentSummaries)
    }

    var shouldDisableConfirmationActions: Bool {
        guard case .awaitingConfirmation = phase else { return false }
        return confirmationActionsFrozen
    }

    func freezeConfirmationActions() {
        confirmationActionsFrozen = true
    }

    func unfreezeConfirmationActions() {
        confirmationActionsFrozen = false
    }

    /// Sync phase with an in-memory plan without embedding the plan graph in `phase`.
    func enterAwaitingConfirmation() {
        setPhase(.awaitingConfirmation)
    }

    func enterExecuting() {
        setPhase(.executing)
    }

    func enterIdle() {
        setPhase(.idle)
    }

    func enterThinking() {
        setPhase(.thinking)
    }

    func enterCompleted(summary: String) {
        setPhase(.completed(summary: summary))
    }

    func enterFailed(message: String) {
        setPhase(.failed(message: message))
    }

    /// Skill extraction and other host-driven overlays that already have an `AgentPhase`.
    func applyHostPhase(_ phase: AgentPhase) {
        setPhase(phase)
    }

    private func setPhase(_ newPhase: AgentPhase) {
        confirmationActionsFrozen = false
        if newPhase != .thinking {
            isReviewing = false
        }
        phase = newPhase
    }

    func clearCompletedPhase() {
        if case .completed = phase { phase = .idle }
    }

    func clearFailedPhase() {
        if case .failed = phase { phase = .idle }
    }

    /// Busy is owned by `SessionOperationGate`.
    func setBusy(_ busy: Bool) {
        isBusy = busy
    }
}
