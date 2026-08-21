//
//  WorkspaceChromeView.swift
//  Sage
//

import AppKit
import SwiftUI

/// Unified titlebar: identity · document · actions / view mode.
/// One row with the traffic lights, not a second stacked toolbar.
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
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            identityCluster
                .font(.system(size: type.caption, weight: .medium))
                .foregroundStyle(.secondary)

            if showsDocumentCluster {
                chromeSeparator
                documentCluster
                    .font(.system(size: type.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: SageDesign.Spacing.medium)

            trailingCluster
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SageDesign.Panel.titlebarContentHeight)
        .padding(.leading, SageDesign.Spacing.large)
        .padding(.trailing, SageDesign.Spacing.large)
    }

    // MARK: - Zones

    @ViewBuilder
    private var identityCluster: some View {
        if isProject {
            projectIdentity
        } else {
            generalIdentity
        }
    }

    private var generalIdentity: some View {
        HStack(spacing: 6) {
            Button(action: openProject) {
                Label("Open Project", systemImage: "folder")
            }
            .help("Open an existing project folder")
            .accessibilityLabel("Open Project")

            Button(action: createProject) {
                Label("New Project", systemImage: "folder.badge.plus")
            }
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
                .help("Recent projects")
                .accessibilityLabel("Recent Projects")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var projectIdentity: some View {
        HStack(alignment: .center, spacing: 6) {
            if let focused {
                projectNameButton(focused)
            } else {
                Text("Opening…")
            }

            if gitBranch != nil {
                branchMenu
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var documentCluster: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            if case .awaitingConfirmation = session.agent.state.phase {
                Text("Awaiting confirmation")
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
        }
        .layoutPriority(0)
    }

    @ViewBuilder
    private var trailingCluster: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            if session.agent.canStartFresh {
                Button {
                    session.draft = ""
                    Task { await session.agent.startFresh() }
                } label: {
                    Label("Start Fresh", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .labelStyle(.titleAndIcon)
                .font(.system(size: type.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .disabled(!session.agent.canStartFresh)
                .help("Start a clean task in this window")
            }

            if isProject {
                projectTabPicker
            }
        }
        .layoutPriority(1)
    }

    private var showsDocumentCluster: Bool {
        if case .awaitingConfirmation = session.agent.state.phase { return true }
        if session.agent.state.threadTitle != nil,
           session.agent.state.activeTask?.events.isEmpty == false {
            return true
        }
        return hasOtherRecentTasks
    }

    private var chromeSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(SageDesign.Chrome.dividerOpacity))
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }

    // MARK: - Project identity

    private func projectNameButton(_ project: ProjectRecord) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([project.rootURL])
        } label: {
            Label(project.name, systemImage: "folder")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help(ProjectPanelActions.displayPath(project.rootPath))
        .accessibilityLabel("Project \(project.name)")
        .accessibilityHint("Show in Finder")
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
            Label(gitBranch ?? "", systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
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

    // MARK: - Recents

    private var recentTaskEntries: [TaskSummary] {
        Array(
            session.agent.state.recentSummaries
                .filter { $0.displayTitle != nil && !$0.isScheduled }
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
                        let title = item.recentsMenuTitle
                        if item.id == session.agent.state.activeTaskID {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            } label: {
                Text(currentTitle ?? "New Task")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
            .disabled(session.agent.state.isBusy)
            .help("Switch to a recent task")
            .accessibilityLabel(
                currentTitle.map { "Current task \($0)" } ?? "Recent tasks"
            )
            .accessibilityHint("Shows recent tasks in this window")
        } else if let currentTitle {
            Text(currentTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .leading)
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
