//
//  AppDelegate.swift
//  Sage
//

import AppKit

extension Notification.Name {
    static let sageOpenSettings = Notification.Name("sage.openSettings")
    static let sageOpenDashboard = Notification.Name("sage.openDashboard")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var agentWindowController: AgentWindowController?
    private var settingsController: SettingsWindowController?
    private var dashboardController: DashboardWindowController?

    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        agentWindowController = AgentWindowController(appState: appState)
        settingsController = SettingsWindowController(appState: appState)
        dashboardController = DashboardWindowController(appState: appState)

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenDashboard),
            name: .sageOpenDashboard,
            object: nil
        )

        startMemoryPressureMonitor()

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

    func showDashboard() {
        dashboardController?.show()
    }

    @objc private func handleToggleAgentWindow() {
        agentWindowController?.toggle()
    }

    @objc private func handleOpenSettings() {
        showSettings()
    }

    @objc private func handleOpenDashboard() {
        showDashboard()
    }

    private func startMemoryPressureMonitor() {
        MemoryPressureMonitor.shared.onPressureChange = { level in
            guard level == .warning || level == .critical else { return }
            Task {
                await LocalModelService.shared.handleMemoryPressure()
            }
        }
        MemoryPressureMonitor.shared.start()
    }
}
