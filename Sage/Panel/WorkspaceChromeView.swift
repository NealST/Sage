//
//  WorkspaceChromeView.swift
//  Sage
//

import AppKit
import SwiftUI

/// Unified titlebar strip: one row with the traffic lights, not a second stacked toolbar.
struct WorkspaceChromeView: View {
    @Environment(AppState.self) private var appState

    var onWillNavigate: () -> Void = {}
    @Binding var gitBranch: String?

    private var focused: ProjectRecord? { appState.agent.focusedProject }
    private var isProject: Bool { focused != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if isProject {
                // Path + branch live in the window title / proxy icon — keep this row quiet.
                projectLeading
            } else {
                generalLeading
            }

            Spacer(minLength: 12)

            trailingActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SageDesign.Panel.titlebarContentHeight)
        // Content already sits below the titlebar; don’t add a second traffic-light gutter.
        .padding(.leading, SageDesign.Spacing.lg)
        .padding(.trailing, SageDesign.Spacing.lg)
    }

    // MARK: - General

    private var generalLeading: some View {
        HStack(spacing: 6) {
            Button {
                openProject()
            } label: {
                Label("Open Project", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.agent.isBusy)
            .help("Open Project…")
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button {
                createProject()
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.agent.isBusy)
            .help("New Project…")
            .keyboardShortcut("n", modifiers: [.command, .shift])

            if !appState.agent.recentProjects.isEmpty {
                recentProjectsMenu
            }
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Project

    private var projectLeading: some View {
        HStack(spacing: 4) {
            // Compact escapes back to General — primary wayfinding.
            Button {
                onWillNavigate()
                Task { await appState.agent.closeProject() }
            } label: {
                Label("General", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(appState.agent.isBusy)
            .help("Return to General")
            .foregroundStyle(.secondary)

            Menu {
                Button("Open Project…") { openProject() }
                    .disabled(appState.agent.isBusy)
                Button("New Project…") { createProject() }
                    .disabled(appState.agent.isBusy)
                if !appState.agent.recentProjects.isEmpty {
                    Divider()
                    ForEach(appState.agent.recentProjects) { project in
                        Button {
                            guard project.id != focused?.id else { return }
                            onWillNavigate()
                            Task { await appState.agent.switchProject(id: project.id) }
                        } label: {
                            Text("\(project.name)  ·  \(ProjectPanelActions.displayPath(project.rootPath))")
                        }
                        .disabled(appState.agent.isBusy)
                    }
                }
                if let focused {
                    Divider()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([focused.rootURL])
                    }
                }
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Projects")
            .disabled(appState.agent.isBusy)
        }
    }

    private var recentProjectsMenu: some View {
        Menu {
            ForEach(appState.agent.recentProjects) { project in
                Button {
                    onWillNavigate()
                    Task { await appState.agent.switchProject(id: project.id) }
                } label: {
                    Text("\(project.name)  ·  \(ProjectPanelActions.displayPath(project.rootPath))")
                }
                .disabled(appState.agent.isBusy)
            }
        } label: {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Recent projects")
        .accessibilityLabel("Recent projects")
        .disabled(appState.agent.isBusy)
    }

    // MARK: - Trailing

    @ViewBuilder
    private var trailingActions: some View {
        if case .awaitingConfirmation = appState.agent.phase {
            Text("Awaiting confirmation")
                .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                )
        }

        if appState.agent.canStartFresh {
            Button("Start Fresh") {
                onWillNavigate()
                Task { await appState.agent.startFresh() }
            }
            .controlSize(.small)
            .disabled(appState.agent.isBusy)
            .help(
                appState.agent.hasPendingPlan
                    ? "Cancel the pending plan and start a clean task here"
                    : "Start a clean task in the current workspace"
            )
        }

        Button {
            NotificationCenter.default.post(name: .sageOpenSettings, object: nil)
        } label: {
            Image(systemName: SageDesign.Symbol.settings)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    // MARK: - Actions

    private func openProject() {
        guard let url = ProjectPanelActions.pickDirectory(
            message: "Choose a project folder"
        ) else { return }
        onWillNavigate()
        Task { await appState.agent.openProject(at: url) }
    }

    private func createProject() {
        guard let created = ProjectPanelActions.promptCreateProject() else { return }
        onWillNavigate()
        Task {
            await appState.agent.createProject(
                parent: created.parent,
                name: created.name,
                gitInit: created.gitInit
            )
        }
    }
}
