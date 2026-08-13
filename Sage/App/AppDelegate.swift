import AppKit

extension Notification.Name {
    static let sageOpenSettings = Notification.Name("sage.openSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsController: SettingsWindowController?
    private var dashboardController: DashboardWindowController?

    let appState = AppState()

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
        startMemoryPressureMonitor()

        Task {
            await appState.bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
