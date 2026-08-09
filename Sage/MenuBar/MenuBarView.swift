//
//  MenuBarView.swift
//  Sage
//

import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    var onOpenAgent: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        Button("Open Sage") {
            onOpenAgent()
        }
        .keyboardShortcut(" ", modifiers: [.command, .shift])

        Button("Open Project…") {
            openProjectFromMenu()
        }
        .disabled(appState.agent.isBusy)
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Button("New Project…") {
            createProjectFromMenu()
        }
        .disabled(appState.agent.isBusy)
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

        if case .awaitingConfirmation = appState.agent.phase {
            Divider()
            Button("Run Plan") {
                onOpenAgent()
                Task { await appState.agent.confirmPendingPlan() }
            }
            .disabled(appState.agent.isBusy)
            Button("Cancel Plan") {
                Task { await appState.agent.cancelPendingPlan() }
            }
            .disabled(appState.agent.isBusy)
        }

        if appState.agent.canStop {
            Divider()
            Button("Stop") {
                appState.agent.stop()
            }
        }

        if case .failed = appState.agent.phase {
            if appState.agent.canRetryFailure {
                Button("Retry") {
                    onOpenAgent()
                    Task { await appState.agent.retryLastFailure() }
                }
            }
            if appState.isConfigurationFailure {
                Button("Open Settings…") {
                    onOpenSettings()
                }
            } else {
                Button("Show Error…") {
                    onOpenAgent()
                }
            }
        }

        Divider()

        Button("Start Fresh") {
            appState.clearDraft()
            Task { await appState.agent.startFresh() }
        }
        .disabled(!appState.agent.canStartFresh)

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
        // Show panels above the menu-bar app; open the agent window first.
        onOpenAgent()
        DispatchQueue.main.async {
            guard let url = ProjectPanelActions.pickDirectory(
                message: "Choose a project folder"
            ) else { return }
            appState.clearDraft()
            Task { await appState.agent.openProject(at: url) }
        }
    }

    private func createProjectFromMenu() {
        onOpenAgent()
        DispatchQueue.main.async {
            guard let created = ProjectPanelActions.promptCreateProject() else { return }
            appState.clearDraft()
            Task {
                await appState.agent.createProject(
                    parent: created.parent,
                    name: created.name,
                    gitInit: created.gitInit
                )
            }
        }
    }
}
