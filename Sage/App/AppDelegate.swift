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

        // "Ask Sage About Selected Text" in every app's Services menu while
        // Sage is running (Info.plist NSServices + this provider).
        NSApp.servicesProvider = self

        UNUserNotificationCenter.current().delegate = self
        TaskCompletionNotifier.registerCategories()

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

    // MARK: - Dock

    /// Folders dropped on the Dock icon (or opened via "Open With") open as
    /// project windows. Files stay with the composer's drag-and-drop — the
    /// PathGuard root validation inside `openProject` rejects anything else.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else { continue }
            Task { await appState.openProject(at: url) }
        }
    }

    /// Dock icon right-click: the project-centric surface. Mirrors the
    /// menu-bar commands so one vocabulary is discoverable from both places.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let openSage = NSMenuItem(
            title: "Open Sage",
            action: #selector(dockOpenSage),
            keyEquivalent: ""
        )
        openSage.target = self
        menu.addItem(openSage)

        let openProject = NSMenuItem(
            title: "Open Project…",
            action: #selector(dockOpenProject),
            keyEquivalent: ""
        )
        openProject.target = self
        menu.addItem(openProject)

        let startFresh = NSMenuItem(
            title: "Start Fresh",
            action: #selector(dockStartFresh),
            keyEquivalent: ""
        )
        startFresh.target = self
        startFresh.isEnabled = appState.agent.canStartFresh
        menu.addItem(startFresh)

        let recents = appState.generalSession.agent.state.recentProjects
        if !recents.isEmpty {
            menu.addItem(.separator())
            for project in recents.prefix(5) {
                let item = NSMenuItem(
                    title: project.name,
                    action: #selector(dockOpenRecent(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = project.id.uuidString
                menu.addItem(item)
            }
        }
        return menu
    }

    @objc private func dockOpenSage() {
        showAgentWindow()
    }

    @objc private func dockOpenProject() {
        openProjectPanel()
    }

    @objc private func dockStartFresh() {
        appState.startFreshInKeySession()
    }

    @objc private func dockOpenRecent(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw)
        else { return }
        Task { await appState.switchToProject(id: id) }
    }

    @objc private func handleOpenSettings() {
        showSettings()
    }

    @objc private func handleOpenSettingsMCP() {
        settingsController?.show(pane: .capabilities, openMCPManage: true)
    }

    // MARK: - Services

    /// Services-menu handler (selector from Info.plist `NSMessage`). Loads
    /// the selection into the composer without sending — selected text is
    /// raw material, the user reviews and presses Return, the same contract
    /// as the starter-prompt chips.
    @objc func askSageAboutSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        Task { @MainActor in
            await appState.askExternally(text, autoSend: false)
        }
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
        let approvalPayload = ApprovalAttentionPayload.fromUserInfo(userInfo)
        guard schedulePayload != nil || taskPayload != nil || approvalPayload != nil else { return }
        let actionID = response.actionIdentifier
        Task { @MainActor in
            if let schedulePayload {
                await handleScheduleNotificationTap(schedulePayload)
            } else if let taskPayload {
                await handleTaskNotificationTap(taskPayload, actionID: actionID)
            } else if let approvalPayload {
                // Both the banner tap and the Review action reveal the window;
                // the decision itself is made in the transcript.
                appState.revealSessionForApproval(projectID: approvalPayload.projectID)
            }
        }
    }

    private func handleTaskNotificationTap(
        _ payload: TaskNotificationPayload,
        actionID: String
    ) async {
        await appState.revealTask(projectID: payload.projectID, taskID: payload.taskID)
        // Retry skips the reveal-then-click round trip. Graceful when the
        // reveal had to re-open the project and re-activate the task (fresh
        // session no longer in .failed) — `canRetryFailure` gates it and the
        // window is up either way.
        if actionID == TaskCompletionNotifier.ActionID.retry,
           appState.keySession.agent.canRetryFailure {
            await appState.keySession.agent.retryLastFailure()
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
