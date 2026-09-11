//
//  MenuBarView.swift
//  Sage
//

import SwiftUI

/// Menu-bar icon as the environment layer: it answers "what is Sage doing"
/// (working / blocked on you / failed) without opening the menu. The leaf
/// glyph never changes so the item keeps a stable identity; state reads
/// from a small trailing badge instead. Attention states outrank running.
struct MenuBarStatusIcon: View {
    @Environment(AppState.self) private var appState

    private enum Status {
        case attentionRequired
        case failed
        case working
        case idle
    }

    private var status: Status {
        for session in appState.allSessions {
            if case .awaitingConfirmation = session.agent.state.phase {
                return .attentionRequired
            }
        }
        var working = false
        for session in appState.allSessions {
            switch session.agent.state.phase {
            case .awaitingConfirmation:
                break

            case .failed:
                return .failed

            case .thinking, .executing:
                working = true

            case .idle, .completed:
                break
            }
        }
        // Schedule failures would otherwise leave Sage looking idle overnight.
        switch appState.attentionSchedule?.status {
        case .failed: return .failed
        case .awaitingConfirmation: return .attentionRequired
        default: break
        }
        if appState.schedules.runningTitle != nil { return .working }
        return working ? .working : .idle
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: SageDesign.Symbol.brand)
            switch status {
            case .attentionRequired:
                badge("exclamationmark.circle.fill", color: SageDesign.Palette.warning)
            case .failed:
                badge("exclamationmark.triangle.fill", color: SageDesign.Palette.danger)
            case .working:
                // Quiet activity marker — secondary, static (menu-bar items
                // shouldn't animate); loud white-backed badges stay for
                // attention states, which outrank running.
                badge(SageDesign.Symbol.stepRunning, color: Color.secondary)
            case .idle:
                EmptyView()
            }
        }
        .accessibilityLabel("Sage — \(statusDescription)")
    }

    private func badge(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .sageFont(8, weight: .bold)
            .foregroundStyle(color)
            .padding(1.5)
            .background(Circle().fill(.white))
            .offset(x: 3, y: 1)
            .accessibilityHidden(true)
    }

    private var statusDescription: String {
        switch status {
        case .attentionRequired: return "attention needed"
        case .failed: return "error"
        case .working: return "working"
        case .idle: return "idle"
        }
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    var onOpenAgent: () -> Void
    var onOpenProject: () -> Void
    var onCreateProject: () -> Void
    var onOpenSettings: () -> Void
    var onOpenDashboard: () -> Void
    var onQuit: () -> Void

    var body: some View {
        Button {
            onOpenAgent()
        } label: {
            Label("Open Sage", systemImage: "macwindow")
        }
        .sageShortcut(
            KeyboardShortcut(.space, modifiers: [.command, .shift]),
            enabled: !appState.hotkeyRegistrationFailed
        )

        Button {
            onOpenProject()
        } label: {
            Label("Open Project…", systemImage: "folder")
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Button {
            onCreateProject()
        } label: {
            Label("New Project…", systemImage: "folder.badge.plus")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

        // Status line — reads as informational, distinct from the commands.
        Label(appState.statusHint, systemImage: "info.circle")

        if appState.hotkeyRegistrationFailed {
            Label("⌘⇧Space could not be registered", systemImage: "exclamationmark.triangle")
            Button("Open Settings…") {
                onOpenSettings()
            }
        }

        if let attention = appState.awaitingConfirmationSession {
            Divider()
            menuConfirmationActions(for: attention)
        }

        if let stoppable = appState.stoppableSession {
            Divider()
            Button {
                stoppable.agent.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        }

        if let failed = appState.failedSession {
            if failed.agent.canRetryFailure {
                Button {
                    appState.makeKeyAndShow(failed)
                    Task { await failed.agent.retryLastFailure() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
            if appState.isConfigurationFailure {
                Button("Open Settings…") {
                    onOpenSettings()
                }
            } else {
                Button {
                    appState.makeKeyAndShow(failed)
                } label: {
                    Label("Show Error…", systemImage: "exclamationmark.bubble")
                }
            }
        }

        if appState.attentionSchedule != nil {
            Divider()
            Button {
                onOpenDashboard()
            } label: {
                Label(
                    appState.attentionSchedule?.status == .failed
                        ? "Schedule Failed — Open Dashboard…"
                        : "Schedule Needs Review — Open Dashboard…",
                    systemImage: "clock.badge.exclamationmark"
                )
            }
        }

        Divider()

        Button {
            appState.revealKeySession()
            appState.clearDraft()
            Task { await appState.agent.startFresh() }
        } label: {
            Label("Start Fresh", systemImage: "arrow.counterclockwise")
        }
        .disabled(!appState.agent.canStartFresh)

        Button {
            onOpenDashboard()
        } label: {
            Label("Dashboard", systemImage: "rectangle.grid.2x2")
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Button {
            onOpenSettings()
        } label: {
            Label("Settings…", systemImage: SageDesign.Symbol.settings)
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button {
            onQuit()
        } label: {
            Label("Quit Sage", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    /// Menu entries for the pending decision. Labels must match what the
    /// transcript card actually asks for — a blind "Run Plan" must never
    /// approve a tool call the user has not seen. Targets the session that
    /// actually holds the pending decision, which may be a project window.
    @ViewBuilder private func menuConfirmationActions(for session: AgentSession) -> some View {
        let agent = session.agent
        switch agent.turnChrome {
        case .toolApproval:
            let remaining = agent.remainingApprovalCount
            Button(remaining > 0 ? "Review Tool Approval… (+\(remaining) queued)" : "Review Tool Approval…") {
                appState.makeKeyAndShow(session)
            }

        case .toolRoundLimit:
            Button("Continue Tool Rounds") {
                appState.makeKeyAndShow(session)
                Task { await agent.confirmToolRoundLimit() }
            }
            .disabled(agent.state.isBusy)
            Button("Finish Now") {
                appState.makeKeyAndShow(session)
                Task { await agent.finishToolRoundLimit() }
            }
            .disabled(agent.state.isBusy)

        case .reviewFailed:
            Button("Retry Review") {
                appState.makeKeyAndShow(session)
                Task { await agent.retryFailedReview() }
            }
            .disabled(agent.state.isBusy)
            Button("Use This Reply") {
                appState.makeKeyAndShow(session)
                Task { await agent.acceptFailedReview() }
            }
            .disabled(agent.state.isBusy)

        case .reviewMustFix:
            Button("Continue Fixing") {
                appState.makeKeyAndShow(session)
                Task { await agent.resumeMustFixReview() }
            }
            .disabled(agent.state.isBusy)
            Button("Keep This Reply") {
                appState.makeKeyAndShow(session)
                Task { await agent.acceptMustFixReview() }
            }
            .disabled(agent.state.isBusy)

        case .reviewOptional:
            Button("Apply Improvements") {
                appState.makeKeyAndShow(session)
                Task { await agent.applyOptionalReview() }
            }
            .disabled(agent.state.isBusy)
            Button("Keep This Reply") {
                appState.makeKeyAndShow(session)
                Task { await agent.acceptOptionalReview() }
            }
            .disabled(agent.state.isBusy)

        case .workPlan, .toolBatch, nil:
            Button("Run Plan") {
                appState.makeKeyAndShow(session)
                Task { await agent.confirmPendingPlan() }
            }
            .disabled(agent.state.isBusy)
            Button("Cancel Plan") {
                appState.makeKeyAndShow(session)
                Task { await agent.cancelPendingPlan() }
            }
            .disabled(agent.state.isBusy)
        }
    }
}
