//
//  AppShortcuts.swift
//  Sage
//
//  App Shortcuts: "Ask Sage to <prompt>" and "Open Sage" from Spotlight /
//  Shortcuts. Intents perform in-process; routing goes through
//  `AppState.current`, which is set in init — a cold launch triggered by the
//  intent still lands after bootstrap.
//

import AppIntents
import Foundation

struct AskSageIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Sage"
    static var description = IntentDescription("Give Sage a task from anywhere.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Message", requestValueDialog: "What should Sage do?")
    var prompt: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return .result() }
        await AppState.current?.askExternally(message, autoSend: true)
        return .result()
    }
}

struct OpenSageIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sage"
    static var description = IntentDescription("Open the Sage agent window.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.current?.showGeneralWindow()
        return .result()
    }
}

struct SageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Free-text parameters can't be interpolated into phrases (AppEntity
        // and AppEnum only), so Ask Sage prompts for the message at run time
        // via `requestValueDialog` — Spotlight: "Sage" → Ask Sage → type.
        AppShortcut(
            intent: AskSageIntent(),
            phrases: ["Ask \(.applicationName)"],
            shortTitle: "Ask Sage",
            systemImageName: "leaf.fill"
        )
        AppShortcut(
            intent: OpenSageIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Sage",
            systemImageName: "macwindow"
        )
    }
}
