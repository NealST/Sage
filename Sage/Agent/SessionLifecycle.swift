//
//  SessionLifecycle.swift
//  Sage
//

import Foundation

/// Window bootstrap / teardown / erase / workspace snapshot.
@MainActor
final class SessionLifecycle {
    private let state: AgentSessionState
    private let planProgress: PlanProgress
    private let taskRepository: any TaskRepository
    private let skillCatalog: () -> SkillCatalog?
    private let skills: SkillSessionController
    private let skillRecall: SkillRecallCoordinator
    private let modelGateway: AgentModelGateway
    private let taskStore: AgentTaskStore
    private let operations: SessionOperationGate

    init(
        state: AgentSessionState,
        planProgress: PlanProgress,
        taskRepository: any TaskRepository,
        skillCatalog: @escaping () -> SkillCatalog?,
        skills: SkillSessionController,
        skillRecall: SkillRecallCoordinator,
        modelGateway: AgentModelGateway,
        taskStore: AgentTaskStore,
        operations: SessionOperationGate
    ) {
        self.state = state
        self.planProgress = planProgress
        self.taskRepository = taskRepository
        self.skillCatalog = skillCatalog
        self.skills = skills
        self.skillRecall = skillRecall
        self.modelGateway = modelGateway
        self.taskStore = taskStore
        self.operations = operations
    }

    /// Boots this window's session. Pass `project` for a project window; `nil` for General.
    func bootstrap(project: ProjectRecord?, reloadCatalog: Bool) async {
        await modelGateway.setRetryStatusHandler { [state] status in
            switch status {
            case .retrying(let attempt, let total, let delay):
                let totalSec = Int(delay.rounded(.up))
                state.retryState = RetryDisplayState(
                    attempt: attempt,
                    maxAttempts: total,
                    totalSeconds: totalSec,
                    secondsRemaining: totalSec
                )
            case .waiting(let seconds):
                state.retryState?.secondsRemaining = seconds
                if seconds <= 0 {
                    state.retryState = nil
                }
            }
        }

        do {
            state.focusedProject = project
            if reloadCatalog {
                await skillCatalog()?.reloadSkills(projectRoot: project?.rootURL)
            } else {
                skillCatalog()?.noteProjectRoot(project?.rootURL)
            }

            let snapshot = try await taskRepository.loadScopedWorkspace(projectID: project?.id)
            applyWorkspaceSnapshot(snapshot)
            // Pin this window's focus regardless of any other session's DB singleton.
            state.focusedProject = project

            if state.activeTask != nil {
                await taskStore.restorePhaseFromActiveTask()
            } else {
                _ = await taskStore.createAndActivateTask(relatedTo: [])
            }
        } catch {
            state.phase = .failed(
                message: "Could not open Sage's local database: \(error.localizedDescription)"
            )
        }
    }

    /// Clears tips and abandons a paused skill choice before this window is destroyed.
    func prepareForWindowClose() async {
        // Lock immediately so composer / submit cannot start work while we drain tips/saves.
        state.isTornDown = true
        await operations.cancelInFlight()

        skills.invalidatePendingSuggestions()
        await abandonAwaitingSkillChoice(
            reason: "Cancelled skill choice — window closed."
        )
        await skills.prepareForTeardown()
        _ = await persistScopeLastActive()
    }

    func eraseAllData() async -> Bool {
        await operations.cancelInFlight()

        do {
            try await taskRepository.eraseAllData()
            state.activeTask = nil
            state.activeTaskID = nil
            state.focusedProject = nil
            state.recentProjects = []
            state.recentSummaries = []
            state.lastAssistantText = nil
            state.contextHint = nil
            state.forceFreshOnNextSubmit = false
            state.activatedSkillNames = []
            planProgress.clear()
            skills.invalidatePendingSuggestions()
            state.phase = .idle
            state.isTornDown = false
            guard await taskStore.createAndActivateTask(relatedTo: []) != nil else {
                return false
            }
            return true
        } catch {
            state.phase = .failed(
                message: "Could not erase local data: \(error.localizedDescription)"
            )
            return false
        }
    }

    /// Sync this window's active task into the shared DB singleton.
    func syncGlobalFocusPointer() async {
        do {
            try await taskRepository.setFocus(
                projectID: state.focusedProject?.id,
                activeTaskID: state.activeTaskID
            )
        } catch {
            // Non-fatal — each window keeps its own in-memory focus.
        }
    }

    func applyWorkspaceSnapshot(_ snapshot: TaskWorkspaceSnapshot) {
        state.focusedProject = snapshot.focusedProject
        state.recentProjects = snapshot.recentProjects
        state.recentSummaries = snapshot.recentSummaries
        state.activeTask = snapshot.activeTask
        state.activeTaskID = snapshot.activeTask?.id ?? snapshot.activeTaskID
        if let plan = snapshot.activeTask?.pendingPlan {
            planProgress.replace(plan)
        } else {
            planProgress.clear()
        }
    }

    func currentWorkspaceSnapshot() -> TaskWorkspaceSnapshot {
        TaskWorkspaceSnapshot(
            focusedProject: state.focusedProject,
            activeTask: state.activeTask,
            recentSummaries: state.recentSummaries,
            recentProjects: state.recentProjects,
            activeTaskID: state.activeTaskID
        )
    }

    static func projectPromptAppendix(for project: ProjectRecord?) -> String {
        guard let project else {
            return """

            ## Active sandbox
            Mode: General. File and shell paths must stay under the user's home directory (~/).
            Default shell working directory is ~.
            """
        }
        return """

        ## Active sandbox
        Mode: Code Project.
        Project name: \(project.name)
        Project root: \(project.rootPath)
        All file reads/writes and shell working directories must stay inside this project root.
        Relative paths resolve against the project root. Prefer project-relative paths.
        Default shell working directory is the project root.
        """
    }

    /// Ends a paused skill-choice turn without running the model.
    func abandonAwaitingSkillChoice(reason: String) async {
        guard case .awaitingSkillChoice = state.phase else { return }
        skills.tips.dismissChoose()
        skillRecall.clearTurnCache()

        let note = AgentEvent(
            kind: .assistantResponse,
            content: reason,
            protected: false
        )
        _ = await taskStore.commit(appendEvents: [note], deleteEventIDs: [], mutate: { _ in })
        state.phase = .idle
    }

    // MARK: - Private

    @discardableResult
    private func persistScopeLastActive() async -> Bool {
        if var current = state.activeTask {
            if case .awaitingConfirmation = state.phase,
               let plan = planProgress.plan ?? current.pendingPlan {
                current.pendingPlan = plan
                current.status = .awaitingApproval
            }
            current.updatedAt = .now
            do {
                try await taskRepository.saveTaskState(current, setActive: false)
                state.activeTask = current
            } catch {
                state.phase = .failed(
                    message: "Could not save task before closing window: \(error.localizedDescription)"
                )
                return false
            }
        }

        guard let activeTaskID = state.activeTaskID else { return true }
        do {
            try await taskRepository.rememberScopeActiveTask(
                projectID: state.focusedProject?.id,
                taskID: activeTaskID
            )
            return true
        } catch {
            state.phase = .failed(
                message: "Could not remember last-active task: \(error.localizedDescription)"
            )
            return false
        }
    }
}
