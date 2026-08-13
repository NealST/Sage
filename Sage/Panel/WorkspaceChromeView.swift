import AppKit
import SwiftUI

/// Unified titlebar strip: one row with the traffic lights, not a second stacked toolbar.
struct WorkspaceChromeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type

    @Binding var gitBranch: String?

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
        HStack(spacing: 4) {
            // Focus General window — does not close this project window or clear its draft.
            Button {
                appState.showGeneralWindow()
            } label: {
                Label("General", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Show General window")
            .foregroundStyle(.secondary)

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
                    Button("Close Project Window") {
                        Task { await appState.closeProjectWindow(projectID: focused.id) }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .labelStyle(.iconOnly)
            .help("Projects")
        }
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
