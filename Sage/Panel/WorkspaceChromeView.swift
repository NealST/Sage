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

    private var focused: ProjectRecord? { session.agent.state.focusedProject }
    private var isProject: Bool { focused != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if isProject {
                projectLeading
            } else {
                generalLeading
            }

            Spacer(minLength: 12)

            trailingActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SageDesign.Panel.titlebarContentHeight)
        .padding(.leading, SageDesign.Spacing.lg)
        .padding(.trailing, SageDesign.Spacing.lg)
    }

    // MARK: - General

    private var generalLeading: some View {
        HStack(spacing: 6) {
            Button("Open Project…", action: openProject)
                .buttonStyle(.borderless)
                .controlSize(.small)

            Button("New Project…", action: createProject)
                .buttonStyle(.borderless)
                .controlSize(.small)

            if !session.agent.state.recentProjects.isEmpty {
                Menu("Recent Projects", systemImage: "clock") {
                    ForEach(session.agent.state.recentProjects) { project in
                        Button {
                            Task { await appState.switchToProject(id: project.id) }
                        } label: {
                            Text("\(project.name)  ·  \(ProjectPanelActions.displayPath(project.rootPath))")
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .labelStyle(.titleAndIcon)
            }
        }
    }

    // MARK: - Project

    private var projectLeading: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.sm) {
            Menu("Projects", systemImage: "folder.badge.gearshape") {
                Button("Open Project…", action: openProject)
                Button("New Project…", action: createProject)
                if !session.agent.state.recentProjects.isEmpty {
                    Divider()
                    ForEach(session.agent.state.recentProjects) { project in
                        Button {
                            guard project.id != focused?.id else { return }
                            Task { await appState.switchToProject(id: project.id) }
                        } label: {
                            Text("\(project.name)  ·  \(ProjectPanelActions.displayPath(project.rootPath))")
                        }
                    }
                }
                if let focused {
                    Divider()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([focused.rootURL])
                    }
                    Button("Copy Root Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(focused.rootPath, forType: .string)
                    }
                    Button("Close Project Window") {
                        Task { await appState.closeProjectWindow(projectID: focused.id) }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .labelStyle(.iconOnly)
            .help("Projects")
            .accessibilityLabel("Projects")

            if let focused {
                projectIdentity(focused)
            }

            if gitBranch != nil {
                branchMenu
            }
        }
    }

    private func projectIdentity(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(project.name)
                .font(.system(size: type.caption, weight: .semibold))
                .lineLimit(1)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([project.rootURL])
            } label: {
                Text(ProjectPanelActions.displayPath(project.rootPath))
                    .font(.system(size: type.micro))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .accessibilityLabel("Project path \(ProjectPanelActions.displayPath(project.rootPath))")
        }
        .frame(maxWidth: 320, alignment: .leading)
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
                        HStack {
                            Text(name)
                            Spacer(minLength: 12)
                            if name == gitBranch {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: type.micro, weight: .semibold))
                Text(gitBranch ?? "")
                    .font(.system(size: type.micro, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .menuStyle(.borderlessButton)
        .help("Switch branch")
        .accessibilityLabel("Branch \(gitBranch ?? "")")
        .disabled(session.agent.state.isBusy)
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

        if session.agent.canStartFresh {
            Button("Start Fresh") {
                session.draft = ""
                Task { await session.agent.startFresh() }
            }
            .controlSize(.small)
            .disabled(session.agent.state.isBusy)
            .help(
                session.agent.state.hasPendingPlan
                    ? "Cancel the pending plan and start a clean task here"
                    : "Start a clean task in this window"
            )
        }
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
