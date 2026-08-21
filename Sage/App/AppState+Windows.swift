//
//  AppState+Windows.swift
//  Sage
//

import AppKit
import Foundation
import SwiftUI

extension AppState {
    // MARK: - Windows

    func bootstrap() async {
        await mcpHub.bootstrap()
        await generalSession.skillCatalog.reloadSkills(projectRoot: nil)
        await generalSession.agent.bootstrap(project: nil, reloadCatalog: false)
        await schedules.start()
        makeKeyAndShow(generalSession)
        revealGeneralWhenReady = false
        if let pending = pendingScheduleReveal {
            pendingScheduleReveal = nil
            await revealScheduledTask(projectID: pending.projectID, taskID: pending.taskID)
        }
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

    /// Opens the matching window and restores that scheduled task after a notification tap.
    func revealScheduledTask(projectID: UUID?, taskID: UUID) async {
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
        await session.agent.bootstrap(project: project)
        await refreshRecentProjectsOnSessions()

        makeKeyAndShow(session)
        return true
    }

    /// Closes a project window and disposes its session (tips die with the window).
    func closeProjectWindow(projectID: UUID) async {
        await disposeProjectSession(projectID: projectID, revealGeneralIfKey: true)
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
        await generalSession.agent.prepareForWindowClose()
    }

    func noteSessionBecameKey(_ session: AgentSession) {
        keySession = session
        isAgentWindowVisible = true
        scheduleFocusPointerSync(for: session)
    }

    func noteSessionHidden(_ session: AgentSession) {
        updateVisibilityFlag()
        _ = session
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
        await session.agent.prepareForWindowClose()
        windowControllers[.project(projectID)]?.destroy()
        windowControllers[.project(projectID)] = nil
        projectSessions[projectID] = nil
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
