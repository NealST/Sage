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

    var statusHint: String {
        if hotkeyRegistrationFailed {
            return "Global shortcut unavailable"
        }
        if !settings.isConfigured {
            return "Set API key in Settings"
        }
        if let title = schedules.runningTitle {
            return "Scheduled: \(Self.compactStatus(title))"
        }
        switch keySession.agent.state.phase {
        case .idle:
            return "Ask Sage to work on your Mac"

        case .thinking:
            return "Thinking…"

        case .awaitingConfirmation:
            switch keySession.agent.turnChrome {
            case .toolRoundLimit:
                return "Tool round limit — continue or finish"

            case .toolApproval:
                return "Tool waiting for approval"

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

        generalSession.resetComposer()
        let didErase = await generalSession.agent.eraseAllData()
        await schedules.reload()
        keySession = generalSession
        makeKeyAndShow(generalSession)
        return didErase
    }
}
