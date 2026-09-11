//
//  WorkspaceChromeView.swift
//  Sage
//

import AppKit
import SwiftUI

/// Unified titlebar: identity · document · actions / view mode.
/// One row with the traffic lights, not a second stacked toolbar.
struct WorkspaceChromeView: View {
    @Environment(AppState.self) var appState
    @Environment(AgentSession.self) var session
    @Environment(\.sageTypography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var gitBranch: String?
    /// Prefetched in the background — building the menu must not shell out.
    @Binding var gitBranches: [String]
    @Binding var branchSwitchError: String?
    @Binding var projectTab: ProjectWorkspaceTab
    /// General window: full task-history browser sheet.
    @State private var isBrowsingTasks = false

    var focused: ProjectRecord? { session.agent.state.focusedProject }
    var isProject: Bool { !session.isGeneral }

    var body: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            identityCluster
                .sageFont(type.caption, weight: .medium)
                .foregroundStyle(.secondary)

            if showsDocumentCluster {
                chromeSeparator
                documentCluster
                    .sageFont(type.caption, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: SageDesign.Spacing.medium)

            trailingCluster
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, SageDesign.Spacing.large)
        .padding(.trailing, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.small)
        .frame(minHeight: SageDesign.Panel.titlebarContentHeight)
        .onReceive(NotificationCenter.default.publisher(for: .sageBrowseTaskHistory)) { note in
            // Sheet lives in the General window only; project windows route
            // the command to their History tab instead.
            guard !isProject,
                  note.object as? AgentSession.Kind == session.kind
            else { return }
            isBrowsingTasks = true
        }
    }

    // MARK: - Zones

    @ViewBuilder var identityCluster: some View {
        if isProject {
            projectIdentity
        } else {
            generalIdentity
        }
    }

    var generalIdentity: some View {
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

    var projectIdentity: some View {
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

    @ViewBuilder var documentCluster: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            if isWorking {
                workingBadge
            }

            if case .awaitingConfirmation = session.agent.state.phase {
                Text("Awaiting confirmation")
                    .foregroundStyle(SageDesign.Palette.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SageDesign.Palette.warning.opacity(0.14))
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

    /// Long turns would otherwise read as a frozen window — this answers
    /// "is this window doing anything" from across the room.
    private var workingBadge: some View {
        Label("Working", systemImage: "circle.dotted")
            .foregroundStyle(.secondary)
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: !reduceMotion
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
            )
            .accessibilityLabel("Sage is working")
    }

    private var isWorking: Bool {
        switch session.agent.state.phase {
        case .thinking, .executing: return true
        case .idle, .awaitingConfirmation, .completed, .failed: return false
        }
    }

    @ViewBuilder var trailingCluster: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            if session.agent.canStartFresh {
                Button {
                    session.resetComposer()
                    Task { await session.agent.startFresh() }
                } label: {
                    Label("Start Fresh", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .labelStyle(.titleAndIcon)
                .sageFont(type.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .disabled(!session.agent.canStartFresh)
                .help("Start a clean task in this window")
            }

            if !isProject, hasTaskHistory {
                Button {
                    isBrowsingTasks = true
                } label: {
                    Label("Browse Tasks", systemImage: "clock")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .labelStyle(.titleAndIcon)
                .sageFont(type.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .help("Search, open, and delete past tasks")
                .sheet(isPresented: $isBrowsingTasks) {
                    TaskHistorySheet(
                        repository: appState.taskRepository,
                        projectID: nil
                    )
                }
            }

            if isProject {
                projectTabPicker
            }
        }
        .layoutPriority(1)
    }

    private var hasTaskHistory: Bool {
        session.agent.state.recentSummaries.contains { !$0.isScheduled }
    }

    var showsDocumentCluster: Bool {
        if isWorking { return true }
        if case .awaitingConfirmation = session.agent.state.phase { return true }
        if session.agent.state.threadTitle != nil,
           session.agent.state.activeTask?.events.isEmpty == false {
            return true
        }
        return hasOtherRecentTasks
    }

    var chromeSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(SageDesign.Chrome.dividerOpacity))
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }
}
