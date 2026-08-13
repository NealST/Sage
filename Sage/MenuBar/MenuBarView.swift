//
//  MenuBarView.swift
//  Sage
//

import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    var onOpenAgent: () -> Void
    var onOpenSettings: () -> Void
    var onOpenDashboard: () -> Void
    var onQuit: () -> Void

    var body: some View {
        Button("Open Sage") {
            onOpenAgent()
        }
        .keyboardShortcut(" ", modifiers: [.command, .shift])

        Button("Open Project…") {
            openProjectFromMenu()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Button("New Project…") {
            createProjectFromMenu()
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

        Text(appState.statusHint)
            .font(.system(size: SageDesign.Typography.captionSize))
            .foregroundStyle(.secondary)
            .lineLimit(1)

        if appState.hotkeyRegistrationFailed {
            Text("⌘⇧Space could not be registered")
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.secondary)
        }

        if case .awaitingConfirmation = appState.agent.state.phase {
            Divider()
            Button("Run Plan") {
                appState.revealKeySession()
                Task { await appState.agent.confirmPendingPlan() }
            }
            .disabled(appState.agent.state.isBusy)
            Button("Cancel Plan") {
                appState.revealKeySession()
                Task { await appState.agent.cancelPendingPlan() }
            }
            .disabled(appState.agent.state.isBusy)
        }

        if appState.agent.canStop {
            Divider()
            Button("Stop") {
                appState.agent.stop()
            }
        }

        if case .failed = appState.agent.state.phase {
            if appState.agent.canRetryFailure {
                Button("Retry") {
                    appState.revealKeySession()
                    Task { await appState.agent.retryLastFailure() }
                }
            }
            if appState.isConfigurationFailure {
                Button("Open Settings…") {
                    onOpenSettings()
                }
            } else {
                Button("Show Error…") {
                    appState.revealKeySession()
                }
            }
        }

        Divider()

        Button("Start Fresh") {
            appState.revealKeySession()
            appState.clearDraft()
            Task { await appState.agent.startFresh() }
        }
        .disabled(!appState.agent.canStartFresh)

        Button("Dashboard") {
            onOpenDashboard()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Button("Settings…") {
            onOpenSettings()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Quit Sage") {
            onQuit()
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func openProjectFromMenu() {
        // Activate without forcing General — cancel must leave keySession alone.
        appState.activateForExternalPanels()
        DispatchQueue.main.async {
            guard let url = ProjectPanelActions.pickDirectory(
                message: "Choose a project folder"
            ) else { return }
            Task { await appState.openProject(at: url) }
        }
    }

    private func createProjectFromMenu() {
        appState.activateForExternalPanels()
        DispatchQueue.main.async {
            guard let created = ProjectPanelActions.promptCreateProject() else { return }
            Task {
                await appState.createProject(
                    parent: created.parent,
                    name: created.name,
                    gitInit: created.gitInit
                )
            }
        }
    }
}
