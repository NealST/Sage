import AppKit
import Foundation
import SwiftUI

/// App-wide coordinator: shared settings/MCP/DB, one AgentSession (+ window) per focus.
@Observable
@MainActor
final class AppState {
    var isAgentWindowVisible: Bool = false
    var hotkeyRegistrationFailed: Bool = false

    let settings: ModelSettings
    /// Shared MCP hub (connections live here). Skills catalogs are per-session.
    let mcpHub: CapabilityStore
    /// Shared persistence for MCP configs.
    let configStore: MCPConfigStore
    /// Shared persistence for skill enablement flags.
    let skillStateStore: SkillStateStore
    let taskRepository: any TaskRepository
    let schedules: ScheduleService

    var generalSession: AgentSession
    var projectSessions: [UUID: AgentSession] = [:]
    var windowControllers: [AgentSession.Kind: AgentWindowController] = [:]
    /// Project windows in open order (dictionary order is not recoverable).
    var openProjectOrder: [UUID] = []
    let openProjectsStore = OpenProjectsStore()
    var isReloadingSkillsAcrossSessions = false
    var pendingSkillsReload = false
    var focusPointerSyncTask: Task<Void, Never>?
    /// Hotkey/menu asked to show General before app bootstrap finished.
    var revealGeneralWhenReady = false
    /// Notification tap arrived before bootstrap finished.
    var pendingScheduleReveal: (projectID: UUID?, taskID: UUID)?

    /// Session whose window is key (menu bar / hotkey target).
    var keySession: AgentSession

    /// Dashboard row to highlight after a script-notification tap.
    var focusedScheduleID: UUID?
    /// Latest `schedule_runs` excerpt for the focused script row.
    var focusedScheduleRunLog: String?

    /// Back-compat for menu bar and settings that still read `appState.agent`.
    var agent: AgentRuntime { keySession.agent }

    var draft: String {
        get { keySession.draft }
        set { keySession.draft = newValue }
    }

    // MARK: - Attention (menu bar)

    /// First session waiting on the user across ALL windows. The status icon
    /// scans every session, so the menu actions must target the same session —
    /// otherwise the icon badges "attention" while the menu offers nothing.
    var awaitingConfirmationSession: AgentSession? {
        if case .awaitingConfirmation = keySession.agent.state.phase { return keySession }
        return allSessions.first { session in
            if case .awaitingConfirmation = session.agent.state.phase { return true }
            return false
        }
    }

    /// First failed session, preferring the key session when it's the failed one.
    var failedSession: AgentSession? {
        if case .failed = keySession.agent.state.phase { return keySession }
        return allSessions.first { session in
            if case .failed = session.agent.state.phase { return true }
            return false
        }
    }

    /// Session with a turn in flight — the key session when it's busy, else
    /// the first busy one.
    var stoppableSession: AgentSession? {
        if keySession.agent.canStop { return keySession }
        return allSessions.first { $0.agent.canStop }
    }

    /// A schedule that failed or is waiting on the user's review. Overnight
    /// failures must be visible from the menu bar, not only in the Dashboard.
    var attentionSchedule: ScheduleRecord? {
        schedules.records.first { $0.status == .failed || $0.status == .awaitingConfirmation }
    }

    var statusHint: String {
        if hotkeyRegistrationFailed {
            return "Global shortcut unavailable"
        }
        if !settings.isConfigured {
            return "Set API key in Settings"
        }
        if let schedule = attentionSchedule {
            return schedule.status == .failed
                ? "Schedule failed — check the Dashboard"
                : "Schedule needs your review"
        }
        if let title = schedules.runningTitle {
            return "Scheduled: \(Self.compactStatus(title))"
        }
        let agent = (awaitingConfirmationSession ?? keySession).agent
        switch agent.state.phase {
        case .idle:
            return "Ask Sage to work on your Mac"

        case .thinking:
            return agent.state.isReviewing ? "Checking the project…" : "Thinking…"

        case .awaitingConfirmation:
            switch agent.turnChrome {
            case .toolRoundLimit:
                return "Tool round limit — continue or finish"

            case .toolApproval:
                return "Tool waiting for approval"

            case .reviewFailed:
                return "Review failed — retry or use this reply"

            case .reviewMustFix:
                return "Review found issues — continue or keep this reply"

            case .reviewOptional:
                return "Review found improvements — choose whether to apply"

            default:
                return "Plan waiting for confirmation"
            }

        case .executing:
            return "Working…"

        case .completed:
            return "Done"

        case .failed(let message):
            return Self.compactStatus(message)
        }
    }

    var isConfigurationFailure: Bool {
        guard case .failed(let message) = keySession.agent.state.phase else { return false }
        return Self.looksLikeConfigurationError(message, isConfigured: settings.isConfigured)
    }

    convenience init() {
        self.init(settings: .shared)
    }

    init(settings: ModelSettings) {
        self.settings = settings
        let configStore = MCPConfigStore()
        let skillStateStore = SkillStateStore()
        self.configStore = configStore
        self.skillStateStore = skillStateStore
        let mcpHub = CapabilityStore(store: configStore)
        self.mcpHub = mcpHub
        let repository = GRDBTaskRepository()
        self.taskRepository = repository

        let general = AgentSession(
            kind: .general,
            settings: settings,
            taskRepository: repository,
            mcpHub: mcpHub,
            skillStateStore: skillStateStore
        )
        self.generalSession = general
        self.keySession = general
        self.schedules = ScheduleService(
            taskRepository: repository,
            settings: settings,
            mcpHub: mcpHub,
            skillStateStore: skillStateStore
        )
        wireSkillsBroadcast(general)
    }

    func clearDraft() {
        keySession.resetComposer()
    }

    @discardableResult
    func eraseAllLocalData() async -> Bool {
        let projectIDs = Array(projectSessions.keys)
        for id in projectIDs {
            await disposeProjectSession(projectID: id, revealGeneralIfKey: false)
        }
        openProjectsStore.discard()

        generalSession.resetComposer()
        generalSession.discardPersistedDraft()
        let didErase = await generalSession.agent.eraseAllData()
        if didErase {
            MessageAttachment.deleteAllManagedCopies()
        }
        await schedules.reload()
        keySession = generalSession
        makeKeyAndShow(generalSession)
        return didErase
    }
}
