//
//  AppState+Windows.swift
//  Sage
//

import AppKit
import Foundation
import SwiftUI

extension AppState {
    // MARK: - Windows

    /// Window identifiers used for presence checks. All start with "Sage" —
    /// see `anySageWindowVisible(excluding:)`.
    enum WindowIdentifier {
        static let settings = "SageSettingsWindow"
        static let dashboard = "SageDashboardWindow"
        static let skillsManage = "SageSkillsManageWindow"
        static let agentPrefix = "SageAgentWindow"
    }

    /// True when at least one Sage-owned window is still visible. The app drops
    /// to accessory only when this is false — so hiding General while the
    /// Dashboard is open stays a regular app. Matches identifiers, never
    /// titles: project windows are titled by project name, and titles localize.
    @MainActor
    static func anySageWindowVisible(excluding excluded: NSWindow? = nil) -> Bool {
        NSApp.windows.contains { window in
            window !== excluded
                && window.isVisible
                && window.identifier?.rawValue.hasPrefix("Sage") == true
        }
    }

    /// Demote to menu-bar-only once the last visible Sage window is gone.
    /// `excluded` is the window about to hide/close (still visible during
    /// `windowWillClose`).
    @MainActor
    static func demoteToAccessoryIfNeeded(excluding excluded: NSWindow? = nil) {
        if !anySageWindowVisible(excluding: excluded) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// First-run placement for the Settings / Dashboard / Skills windows:
    /// centered like the agent window, then nudged down the cascade so the
    /// first-open stack of Sage windows stays readable instead of perfectly
    /// overlapping. Reuses the 22pt-per-window offset from the agent
    /// project-window cascade.
    @MainActor
    static func cascadeCenteredFrame(for window: NSWindow) -> NSRect {
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = window.frame.size
        let otherSageWindows = NSApp.windows.filter {
            $0 !== window && $0.isVisible
                && $0.identifier?.rawValue.hasPrefix("Sage") == true
        }.count
        let maxOffset = max(0, min(visible.width - size.width, visible.height - size.height) / 2)
        let offset = min(CGFloat(otherSageWindows) * 22, maxOffset)
        let origin = NSPoint(
            x: visible.midX - size.width / 2 + offset,
            y: visible.midY - size.height / 2 - offset
        )
        return NSRect(origin: origin, size: size)
    }

    func bootstrap() async {
        await mcpHub.bootstrap()
        await generalSession.skillCatalog.reloadSkills(projectRoot: nil)
        await generalSession.agent.bootstrap(project: nil, reloadCatalog: false)
        await generalSession.restorePersistedDraft()
        await schedules.start()
        makeKeyAndShow(generalSession)
        revealGeneralWhenReady = false
        await restoreOpenProjectWindows()
        if let pending = pendingScheduleReveal {
            pendingScheduleReveal = nil
            await revealTask(projectID: pending.projectID, taskID: pending.taskID)
        }
    }

    /// Reopens the project windows that were open at quit, in their saved
    /// order. Folders that moved or vanished since the last run are skipped
    /// quietly — each successful open rewrites the list, so it self-heals.
    private func restoreOpenProjectWindows() async {
        var restored = false
        for projectID in openProjectsStore.load() {
            guard let project = try? await taskRepository.loadProject(id: projectID),
                  FileManager.default.fileExists(atPath: project.rootURL.path)
            else { continue }
            restored = true
            await openOrFocusProject(project)
        }
        if restored {
            // Each restored window shows key as it comes back; land on General
            // so launch focus matches the no-restore case.
            makeKeyAndShow(generalSession)
        }
    }

    // MARK: - Menu commands

    /// Task ⌘⇧F — the key session's Start Fresh (mirrors the menu-bar item).
    func startFreshInKeySession() {
        revealKeySession()
        clearDraft()
        Task { await agent.startFresh() }
    }

    /// Task ⌘E — exports the key session's active transcript as Markdown.
    func exportKeySessionTask() {
        guard let task = keySession.agent.state.activeTask, !task.events.isEmpty else { return }
        TaskMarkdownExporter.exportThroughSavePanel(for: task)
    }

    /// Task ⌘F — opens the transcript find bar in the key session. Project
    /// windows switch to their Task tab first; the pane needs a beat to mount
    /// before it can receive the activation.
    func findInKeySessionTask() {
        if keySessionIsProject {
            selectWorkspaceTab(.task)
        } else {
            revealKeySession()
        }
        let kind = keySession.kind
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            NotificationCenter.default.post(name: .sageFindInTranscript, object: kind)
        }
    }

    /// Whether the key session's active task has transcript content (⌘E / ⌘F).
    var keySessionHasTranscript: Bool {
        keySession.agent.state.activeTask?.events.isEmpty == false
    }

    var keySessionIsProject: Bool {
        !keySession.isGeneral
    }

    /// Any session with non-scheduled history is browsable: the General sheet
    /// searches everywhere; a project window's History tab covers that project.
    var hasBrowsableTaskHistory: Bool {
        allSessions.contains { session in
            session.agent.state.recentSummaries.contains { !$0.isScheduled }
        }
    }

    /// Task ⌘⇧H — General opens the history sheet; project windows jump to
    /// their History tab (same content, already embedded).
    func browseTasksInKeySession() {
        if keySession.isGeneral {
            NotificationCenter.default.post(
                name: .sageBrowseTaskHistory,
                object: keySession.kind
            )
        } else {
            selectWorkspaceTab(.history)
        }
    }

    /// View ⌘1/⌘2/⌘3 — tabs exist only in project windows.
    func selectWorkspaceTab(_ tab: ProjectWorkspaceTab) {
        guard keySessionIsProject else { return }
        revealKeySession()
        NotificationCenter.default.post(
            name: .sageSelectWorkspaceTab,
            object: keySession.kind,
            userInfo: [ProjectWorkspaceTab.notificationKey: tab.rawValue]
        )
    }

    func toggleKeyAgentWindow() {
        let kind = keySession.kind
        if let controller = windowControllers[kind] {
            controller.toggle()
        } else if keySession.isGeneral, !keySession.agent.state.didBootstrap {
            // Launch still loading — show as soon as bootstrap finishes.
            revealGeneralWhenReady = true
        } else {
            showGeneralWindow()
        }
    }

    /// Reveal whichever session is currently key (menu Run Plan / Retry / hotkey peer).
    func revealKeySession() {
        makeKeyAndShow(keySession)
    }

    /// Bring Sage forward for modal panels without changing which session is key.
    func activateForExternalPanels() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the matching window and restores a task after a notification tap
    /// (schedule banner or interactive task banner — same reveal).
    func revealTask(projectID: UUID?, taskID: UUID) async {
        clearFocusedSchedule()
        if !generalSession.agent.state.didBootstrap {
            pendingScheduleReveal = (projectID, taskID)
            return
        }
        activateForExternalPanels()
        if let projectID {
            do {
                guard let project = try await taskRepository.loadProject(id: projectID) else {
                    reportNavigationFailure("Could not find that project.")
                    return
                }
                _ = await openOrFocusProject(project)
            } catch {
                reportNavigationFailure("Could not open project: \(error.localizedDescription)")
                return
            }
        } else {
            showGeneralWindow()
        }
        await keySession.agent.activateTask(taskID)
    }

    /// Highlights a schedule in Dashboard (script notification tap).
    func revealSchedule(_ id: UUID) async {
        focusedScheduleID = id
        activateForExternalPanels()
        focusedScheduleRunLog = (try? await taskRepository.latestScheduleRun(scheduleID: id))?.outputExcerpt
    }

    /// Clears Dashboard highlight from a script-notification tap.
    func clearFocusedSchedule() {
        focusedScheduleID = nil
        focusedScheduleRunLog = nil
    }

    func showGeneralWindow() {
        if !generalSession.agent.state.didBootstrap {
            revealGeneralWhenReady = true
            return
        }
        makeKeyAndShow(generalSession)
    }

    /// Opens an existing directory as a project window (or focuses it if already open).
    @discardableResult
    func openProject(at url: URL) async -> Bool {
        do {
            let project = try await taskRepository.openProject(rootURL: url, displayName: nil)
            return await openOrFocusProject(project)
        } catch {
            reportNavigationFailure("Could not open project: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func createProject(parent parentURL: URL, name: String, gitInit: Bool) async -> Bool {
        do {
            let project = try await taskRepository.createProject(
                parentURL: parentURL,
                name: name,
                gitInit: gitInit
            )
            return await openOrFocusProject(project)
        } catch {
            reportNavigationFailure("Could not create project: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func switchToProject(id: UUID) async -> Bool {
        do {
            guard let project = try await taskRepository.loadProject(id: id) else {
                reportNavigationFailure("Could not find that project.")
                return false
            }
            let opened = try await taskRepository.openProject(
                rootURL: project.rootURL,
                displayName: project.name
            )
            return await openOrFocusProject(opened)
        } catch {
            reportNavigationFailure("Could not switch project: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func openOrFocusProject(_ project: ProjectRecord) async -> Bool {
        if let existing = projectSessions[project.id] {
            makeKeyAndShow(existing)
            return true
        }

        let session = AgentSession(
            kind: .project(project.id),
            settings: settings,
            taskRepository: taskRepository,
            mcpHub: mcpHub,
            skillStateStore: skillStateStore
        )
        // Pin focus before bootstrap awaits so a premature paint can't look like General.
        session.agent.state.focusedProject = project
        wireSkillsBroadcast(session)
        projectSessions[project.id] = session
        openProjectOrder.append(project.id)
        openProjectsStore.save(openProjectOrder)
        await session.agent.bootstrap(project: project)
        await session.restorePersistedDraft()
        await refreshRecentProjectsOnSessions()

        makeKeyAndShow(session)
        return true
    }

    /// Closes a project window and disposes its session (tips die with the
    /// window). The only close path that rewrites the persisted window list —
    /// quit must keep it for the next launch's restore.
    func closeProjectWindow(projectID: UUID) async {
        await disposeProjectSession(projectID: projectID, revealGeneralIfKey: true)
        openProjectsStore.save(openProjectOrder)
    }

    /// Menu Quit / Cmd+Q: same drain as closing every window, then the process can exit.
    func prepareForQuit() async {
        focusPointerSyncTask?.cancel()
        focusPointerSyncTask = nil
        await schedules.prepareForQuit()
        let projectIDs = Array(projectSessions.keys)
        for id in projectIDs {
            await disposeProjectSession(projectID: id, revealGeneralIfKey: false)
        }
        generalSession.flushDraftPersist()
        await generalSession.agent.prepareForWindowClose()
    }

    func noteSessionBecameKey(_ session: AgentSession) {
        keySession = session
        isAgentWindowVisible = true
        scheduleFocusPointerSync(for: session)
        refreshDockBadge()
    }

    func noteSessionHidden(_ session: AgentSession) {
        updateVisibilityFlag()
        _ = session
    }

    /// Dock tile badge — how many windows are waiting on the user. Answers
    /// "why is Sage asking for me" without opening anything. Accessory mode
    /// has no Dock icon, so the badge is refreshed back in whenever the app
    /// goes regular again.
    @MainActor
    func refreshDockBadge() {
        let count = allSessions.filter { session in
            if case .awaitingConfirmation = session.agent.state.phase { return true }
            return false
        }.count
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// After a skill toggle on one session catalog, re-apply disk flags on the others.
    func syncSkillEnablement(from source: AgentSession) async {
        await source.skillCatalog.flushSkillEnablement()
        for session in allSessions where session.kind != source.kind {
            await session.skillCatalog.refreshSkillEnablementFromDisk()
        }
    }

    /// Rescan skill folders once per distinct project root, then apply to every session.
    func reloadSkillsAcrossSessions() async {
        if isReloadingSkillsAcrossSessions {
            pendingSkillsReload = true
            return
        }
        isReloadingSkillsAcrossSessions = true
        defer { isReloadingSkillsAcrossSessions = false }

        repeat {
            pendingSkillsReload = false

            let enablement = await generalSession.skillCatalog.loadSkillEnablementFromDisk()
            let registry = SkillRegistry.shared
            let userSkills = await registry.scanUserSkills()
            var mergedByRootPath: [String: [SkillRecord]] = [:]
            var keptPaths = Set<String>()

            for session in allSessions {
                let root = session.agent.state.focusedProject?.rootURL
                let merged: [SkillRecord]
                if let root {
                    let key = root.path
                    if let cached = mergedByRootPath[key] {
                        merged = cached
                    } else {
                        let projectSkills = await registry.scanProjectSkills(root: root)
                        let value = SkillRegistry.mergeSkills(project: projectSkills, user: userSkills)
                        mergedByRootPath[key] = value
                        merged = value
                    }
                } else {
                    merged = userSkills
                }
                session.skillCatalog.applyScanned(merged, enablement: enablement, projectRoot: root)
                keptPaths.formUnion(merged.map(\.path))
            }

            await registry.pruneCaches(keepingPaths: keptPaths)
        } while pendingSkillsReload
    }

    // MARK: - Internals

    var allSessions: [AgentSession] {
        [generalSession] + Array(projectSessions.values)
    }

    func makeKeyAndShow(_ session: AgentSession) {
        if session.isGeneral, !session.agent.state.didBootstrap {
            revealGeneralWhenReady = true
            return
        }
        if case .project = session.kind, !session.agent.state.didBootstrap {
            // Project windows are only shown after bootstrap in openOrFocusProject.
            return
        }
        keySession = session
        windowController(for: session).show()
        isAgentWindowVisible = true
        scheduleFocusPointerSync(for: session)
    }

    func scheduleFocusPointerSync(for session: AgentSession) {
        focusPointerSyncTask?.cancel()
        let agent = session.agent
        focusPointerSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await agent.syncGlobalFocusPointer()
        }
    }

    func wireSkillsBroadcast(_ session: AgentSession) {
        session.agent.onSkillsCatalogChanged = { [weak self] in
            await self?.reloadSkillsAcrossSessions()
        }
        session.agent.onTaskSettled = { [weak self] taskID, plan, outcome in
            guard let self else { return }
            let watching = self.isWatchingTask(taskID)
            let postNotification: Bool
            switch outcome {
            case .completed:
                postNotification = !watching

            case .cancelled, .failed:
                postNotification = true
            }
            await self.schedules.noteSpawnedTaskSettled(
                taskID: taskID,
                plan: plan,
                outcome: outcome,
                postNotification: postNotification
            )
            await self.postInteractiveTaskBanner(session: session, taskID: taskID, outcome: outcome)
        }
    }

    /// A task the user started in a window settles while they are away: the
    /// Dock bounce is easy to miss and expires; a banner survives in
    /// Notification Center and taps back into the task. Schedule-owned tasks
    /// are skipped — the schedule path already posts with its own cadence.
    private func postInteractiveTaskBanner(
        session: AgentSession,
        taskID: UUID,
        outcome: AgentTaskSettlement
    ) async {
        // App activation is too coarse: with Settings, the Skills window, or
        // another project's window focused, the app is active but this
        // transcript is unwatched. The owning window being key is what
        // "the user is looking at it" means.
        guard windowControllers[session.kind]?.isKey != true else { return }
        switch outcome {
        case .completed, .failed:
            break

        case .cancelled:
            // User-initiated stop — no news is good news.
            return
        }
        guard let record = try? await taskRepository.loadTaskMetadata(id: taskID),
              record.originScheduleID == nil
        else { return }

        let subject = TopicDriftDetector.threadLabel(
            topic: record.topic,
            abstract: record.abstract,
            summary: record.summary
        ) ?? "Task"
        let scope = session.agent.state.focusedProject?.name ?? "Sage"
        switch outcome {
        case .completed:
            TaskCompletionNotifier.post(
                TaskNotificationPayload(
                    projectID: session.projectID,
                    taskID: taskID,
                    title: "\(scope) — finished",
                    body: subject
                ),
                playsSound: true
            )

        case .failed(let message):
            TaskCompletionNotifier.post(
                TaskNotificationPayload(
                    projectID: session.projectID,
                    taskID: taskID,
                    title: "\(scope) — failed",
                    body: String(message.prefix(160))
                ),
                playsSound: true
            )

        case .cancelled:
            break
        }
    }

    /// Navigation failures should not dirty an unrelated busy project transcript.
    func reportNavigationFailure(_ message: String) {
        if keySession.agent.state.isBusy || keySession.agent.state.hasPendingPlan {
            generalSession.agent.reportFailure(message)
            makeKeyAndShow(generalSession)
        } else {
            keySession.agent.reportFailure(message)
            revealKeySession()
        }
    }

    func isWatchingTask(_ taskID: UUID) -> Bool {
        if generalSession.agent.state.activeTaskID == taskID { return true }
        return projectSessions.values.contains { $0.agent.state.activeTaskID == taskID }
    }

    func disposeProjectSession(projectID: UUID, revealGeneralIfKey: Bool) async {
        guard let session = projectSessions[projectID] else { return }
        let wasKey = keySession.kind == .project(projectID)
        session.flushDraftPersist()
        await session.agent.prepareForWindowClose()
        windowControllers[.project(projectID)]?.destroy()
        windowControllers[.project(projectID)] = nil
        projectSessions[projectID] = nil
        openProjectOrder.removeAll { $0 == projectID }
        if wasKey, revealGeneralIfKey {
            makeKeyAndShow(generalSession)
        } else if wasKey {
            keySession = generalSession
        }
        updateVisibilityFlag()
    }

    func windowController(for session: AgentSession) -> AgentWindowController {
        if let existing = windowControllers[session.kind] {
            return existing
        }
        let controller = AgentWindowController(appState: self, session: session)
        windowControllers[session.kind] = controller
        return controller
    }

    func updateVisibilityFlag() {
        isAgentWindowVisible = windowControllers.values.contains { $0.isVisible }
        refreshDockBadge()
    }

    func refreshRecentProjectsOnSessions() async {
        do {
            let projects = try await taskRepository.listRecentProjects(limit: 12)
            generalSession.agent.applyRecentProjects(projects)
            for session in projectSessions.values {
                session.agent.applyRecentProjects(projects)
            }
        } catch {
            // Non-fatal — menu still works from whichever runtime last loaded.
        }
    }

    static func looksLikeConfigurationError(_ message: String, isConfigured: Bool) -> Bool {
        let lower = message.lowercased()
        return !isConfigured
            || lower.contains("api key")
            || lower.contains("settings")
            || lower.contains("base url")
            || lower.contains("not configured")
            || lower.contains("401")
            || lower.contains("403")
    }

    static func compactStatus(_ message: String) -> String {
        let trimmed = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
