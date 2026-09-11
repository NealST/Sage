import AppKit
import UserNotifications

extension Notification.Name {
    static let sageOpenSettings = Notification.Name("sage.openSettings")
    /// Opens Settings on the Capabilities pane with the MCP manage sheet up.
    static let sageOpenSettingsMCP = Notification.Name("sage.openSettingsMCP")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var settingsController: SettingsWindowController?
    private var dashboardController: DashboardWindowController?

    let appState = AppState()
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = self

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
            selector: #selector(handleOpenSettingsMCP),
            name: .sageOpenSettingsMCP,
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func finishTerminate() {
        HotkeyManager.shared.stop()
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

    /// Shared by the menu-bar menu and the File-menu commands. Activates
    /// first (without forcing General) so the open panel owns the focus and
    /// canceling it leaves keySession alone.
    func openProjectPanel() {
        appState.activateForExternalPanels()
        DispatchQueue.main.async { [self] in
            guard let url = ProjectPanelActions.pickDirectory(
                message: "Choose a project folder"
            ) else { return }
            Task { await appState.openProject(at: url) }
        }
    }

    func createProjectPanel() {
        appState.activateForExternalPanels()
        DispatchQueue.main.async { [self] in
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

    @objc private func handleToggleAgentWindow() {
        toggleAgentWindow()
    }

    @objc private func handleOpenSettings() {
        showSettings()
    }

    @objc private func handleOpenSettingsMCP() {
        settingsController?.show(pane: .capabilities, openMCPManage: true)
    }

    // MARK: - Notifications

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        completionHandler()
        let schedulePayload = ScheduleNotificationPayload.fromUserInfo(userInfo)
        let taskPayload = TaskNotificationPayload.fromUserInfo(userInfo)
        guard schedulePayload != nil || taskPayload != nil else { return }
        Task { @MainActor in
            if let schedulePayload {
                await handleScheduleNotificationTap(schedulePayload)
            } else if let taskPayload {
                await appState.revealTask(projectID: taskPayload.projectID, taskID: taskPayload.taskID)
            }
        }
    }

    private func handleScheduleNotificationTap(_ payload: ScheduleNotificationPayload) async {
        if let taskID = payload.taskID {
            await appState.revealTask(projectID: payload.projectID, taskID: taskID)
        } else {
            await appState.revealSchedule(payload.scheduleID)
            showDashboard()
        }
    }
}
