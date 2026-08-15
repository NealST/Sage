//
//  WorkspaceChromeView.swift
//  Sage
//

import AppKit
import SwiftUI

/// Unified titlebar strip: one row with the traffic lights, not a second stacked toolbar.
struct WorkspaceChromeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type

    @Binding var gitBranch: String?
    @Binding var branchSwitchError: String?
    @Binding var projectTab: ProjectWorkspaceTab

    private var focused: ProjectRecord? { session.agent.state.focusedProject }
    private var isProject: Bool { !session.isGeneral }

    var body: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.sm) {
            if isProject {
                projectLeading
            } else {
                generalLeading
            }

            trailingActions

            Spacer(minLength: SageDesign.Spacing.md)

            // Flush trailing edge with the composer field (same `.lg` inset).
            if isProject {
                projectTabPicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SageDesign.Panel.titlebarContentHeight)
        .padding(.leading, SageDesign.Spacing.lg)
        .padding(.trailing, SageDesign.Spacing.lg)
    }

    // MARK: - General

    private var generalLeading: some View {
        HStack(spacing: 6) {
            Button(action: openProject) {
                Label("Open Project", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .labelStyle(.titleAndIcon)
            .help("Open an existing project folder")
            .accessibilityLabel("Open Project")

            Button(action: createProject) {
                Label("New Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .labelStyle(.titleAndIcon)
            .help("Create a new project folder")
            .accessibilityLabel("New Project")

            if !session.agent.state.recentProjects.isEmpty {
                Menu {
                    ForEach(session.agent.state.recentProjects) { project in
                        Button {
                            Task { await appState.switchToProject(id: project.id) }
                        } label: {
                            Text("\(project.name)  ·  \(ProjectPanelActions.displayPath(project.rootPath))")
                        }
                    }
                } label: {
                    Label("Recent Projects", systemImage: "clock")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .labelStyle(.titleAndIcon)
                .help("Recent projects")
                .accessibilityLabel("Recent Projects")
            }
        }
    }

    // MARK: - Project

    private var projectLeading: some View {
        HStack(alignment: .center, spacing: 4) {
            if let focused {
                projectPathLabel(focused)
            } else {
                Text("Opening…")
                    .font(.system(size: type.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if gitBranch != nil {
                branchMenu
            }
        }
        // Keep path + branch as one compact cluster; don’t let the menu stretch.
        .fixedSize(horizontal: true, vertical: false)
    }

    private func projectPathLabel(_ project: ProjectRecord) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([project.rootURL])
        } label: {
            Text(ProjectPanelActions.displayPath(project.rootPath))
                .font(.system(size: type.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        .accessibilityLabel("Project path \(ProjectPanelActions.displayPath(project.rootPath))")
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var branchMenu: some View {
        Menu {
            let root = focused?.rootURL
            let branches = root.map { GitBranchReader.localBranches(inProjectRoot: $0) } ?? []
            if branches.isEmpty {
                Text("No local branches")
            } else {
                ForEach(branches, id: \.self) { name in
                    Button {
                        switchToBranch(name)
                    } label: {
                        if name == gitBranch {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                Text(gitBranch ?? "")
                    .lineLimit(1)
            }
            .font(.system(size: type.caption, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .help("Switch branch")
        .accessibilityLabel("Branch \(gitBranch ?? "")")
        .disabled(session.agent.state.isBusy)
    }

    private var projectTabPicker: some View {
        Picker("Workspace", selection: $projectTab) {
            ForEach(ProjectWorkspaceTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 240)
        .labelsHidden()
        .accessibilityLabel("Workspace")
        .help("Switch between Task, Files, and History")
    }

    // MARK: - Trailing

    @ViewBuilder
    private var trailingActions: some View {
        if case .awaitingConfirmation = session.agent.state.phase {
            Text("Awaiting confirmation")
                .font(.system(size: type.micro, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                )
        }

        if let title = session.agent.state.threadTitle,
           session.agent.state.activeTask?.events.isEmpty == false {
            recentTasksControl(currentTitle: title)
        } else if hasOtherRecentTasks {
            recentTasksControl(currentTitle: nil)
        }

        if session.agent.canStartFresh {
            Button("Start Fresh") {
                session.draft = ""
                Task { await session.agent.startFresh() }
            }
            .controlSize(.small)
            .disabled(session.agent.state.isBusy && session.agent.state.topicDriftOffer == nil)
            .help("Start a clean task in this window")
        }
    }

    private var recentTaskEntries: [TaskSummary] {
        Array(
            session.agent.state.recentSummaries
                .filter { $0.displayTitle != nil }
                .prefix(10)
        )
    }

    private var hasOtherRecentTasks: Bool {
        recentTaskEntries.contains { $0.id != session.agent.state.activeTaskID }
    }

    @ViewBuilder
    private func recentTasksControl(currentTitle: String?) -> some View {
        if hasOtherRecentTasks {
            Menu {
                ForEach(recentTaskEntries) { item in
                    Button {
                        selectRecentTask(item.id)
                    } label: {
                        let title = item.displayTitle ?? "Task"
                        if item.id == session.agent.state.activeTaskID {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            } label: {
                Text(currentTitle ?? "New Task")
                    .font(.system(size: type.micro, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
            .layoutPriority(0)
            .disabled(session.agent.state.isBusy)
            .help("Switch to a recent task")
            .accessibilityLabel(
                currentTitle.map { "Current task \($0)" } ?? "Recent tasks"
            )
            .accessibilityHint("Shows recent tasks in this window")
        } else if let currentTitle {
            Text(currentTitle)
                .font(.system(size: type.micro, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .leading)
                .layoutPriority(0)
                .help("Current task")
                .accessibilityLabel("Current task \(currentTitle)")
        }
    }

    private func selectRecentTask(_ id: UUID) {
        guard id != session.agent.state.activeTaskID else { return }
        projectTab = .task
        session.draft = ""
        Task { await session.agent.activateTask(id) }
    }

    // MARK: - Actions

    private func switchToBranch(_ name: String) {
        guard let root = focused?.rootURL else { return }
        guard name != gitBranch else { return }
        branchSwitchError = nil
        let rootURL = root
        Task.detached(priority: .userInitiated) {
            let error = GitBranchReader.checkout(branch: name, inProjectRoot: rootURL)
            let refreshed = GitBranchReader.currentBranch(inProjectRoot: rootURL)
            await MainActor.run {
                if let error {
                    branchSwitchError = error
                } else {
                    gitBranch = refreshed
                    branchSwitchError = nil
                }
            }
        }
    }

    private func openProject() {
        guard let url = ProjectPanelActions.pickDirectory(
            message: "Choose a project folder"
        ) else { return }
        Task { await appState.openProject(at: url) }
    }

    private func createProject() {
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
