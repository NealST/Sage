//
//  MenuBarView.swift
//  Sage
//

import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    var onOpenHUD: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        Button("Open Sage") {
            onOpenHUD()
        }
        .keyboardShortcut(" ", modifiers: [.command, .shift])

        Text(appState.statusHint)
            .font(.system(size: SageDesign.Typography.captionSize))
            .foregroundStyle(.secondary)

        Divider()

        Button("Settings…") {
            onOpenSettings()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button("New Chat") {
            appState.agent.createSession()
            onOpenHUD()
        }

        Button("Clear Current Chat") {
            Task { await appState.agent.clearActiveSession() }
        }

        Divider()

        Button("Quit Sage") {
            onQuit()
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
