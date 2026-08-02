//
//  AppDelegate.swift
//  Sage
//

import AppKit

extension Notification.Name {
    static let sageOpenSettings = Notification.Name("sage.openSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var agentWindowController: AgentWindowController?
    private var settingsController: SettingsWindowController?

    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        agentWindowController = AgentWindowController(appState: appState)
        settingsController = SettingsWindowController(appState: appState)

        appState.hotkeyRegistrationFailed = !HotkeyManager.shared.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleAgentWindow),
            name: .sageToggleAgentWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: .sageOpenSettings,
            object: nil
        )

        Task {
            await appState.capabilities.bootstrap()
            await appState.agent.bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func toggleAgentWindow() {
        agentWindowController?.toggle()
    }

    func showAgentWindow() {
        agentWindowController?.show()
    }

    func showSettings() {
        settingsController?.show()
    }

    @objc private func handleToggleAgentWindow() {
        agentWindowController?.toggle()
    }

    @objc private func handleOpenSettings() {
        showSettings()
    }
}
