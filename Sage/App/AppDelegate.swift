import AppKit

extension Notification.Name {
    static let sageOpenSettings = Notification.Name("sage.openSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsController: SettingsWindowController?
    private var dashboardController: DashboardWindowController?

    let appState = AppState()
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        Task {
            await appState.bootstrap()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuitting { return .terminateLater }
        isQuitting = true
        Task { @MainActor in
            await appState.prepareForQuit()
            finishTerminate()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        finishTerminate()
    }

    private func finishTerminate() {
        HotkeyManager.shared.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func toggleAgentWindow() {
        appState.toggleKeyAgentWindow()
    }

    func showAgentWindow() {
        appState.showGeneralWindow()
    }

    func showSettings() {
        settingsController?.show()
    }

    func showDashboard() {
        dashboardController?.show()
    }

    @objc private func handleToggleAgentWindow() {
        toggleAgentWindow()
    }

    @objc private func handleOpenSettings() {
        showSettings()
    }
}
