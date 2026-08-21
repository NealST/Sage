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

    var focused: ProjectRecord? { session.agent.state.focusedProject }
    var isProject: Bool { !session.isGeneral }

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

    @ViewBuilder var trailingCluster: some View {
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

    var showsDocumentCluster: Bool {
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
