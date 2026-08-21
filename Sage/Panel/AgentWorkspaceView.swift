//
//  AgentWorkspaceView.swift
//  Sage
//

import AppKit
import SwiftUI

private struct PathGuardPolicyKey: EnvironmentKey {
    static let defaultValue: PathGuard.Policy = .home
}

extension EnvironmentValues {
    var pathGuardPolicy: PathGuard.Policy {
        get { self[PathGuardPolicyKey.self] }
        set { self[PathGuardPolicyKey.self] = newValue }
    }
}

struct AgentWorkspaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(\.sageTypography) private var type
    @FocusState private var isInputFocused: Bool
    @State private var stickToBottom = true
    @State private var gitBranch: String?
    @State private var branchSwitchError: String?
    @State private var projectTab: ProjectWorkspaceTab = .task

    private var isProjectWindow: Bool {
        !session.isGeneral
    }

    private var isWorkspaceReady: Bool {
        session.agent.state.didBootstrap
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceChromeView(
                gitBranch: $gitBranch,
                branchSwitchError: $branchSwitchError,
                projectTab: $projectTab
            )

            if let branchSwitchError, !branchSwitchError.isEmpty {
                branchErrorBanner(branchSwitchError)
            }

            if isWorkspaceReady {
                if projectTab == .task || !isProjectWindow {
                    TranscriptNoticeBar()
                        .animation(
                            SageDesign.Motion.expandAnimation,
                            value: session.agent.state.topicDriftOffer?.triggeringUserEventID
                        )
                        .animation(
                            SageDesign.Motion.expandAnimation,
                            value: session.agent.state.contextHint
                        )
                }

                Divider().opacity(SageDesign.Chrome.dividerOpacity)

                if isProjectWindow {
                    projectTabBody
                } else {
                    taskPane
                }
            } else {
                Divider().opacity(SageDesign.Chrome.dividerOpacity)
                bootstrapPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.pathGuardPolicy, session.agent.state.pathGuardPolicy)
        .environment(session.agent.streamingPlayback)
        .onAppear {
            focusInputSoon()
            refreshGitBranch()
            updateWindowTitle()
            projectTab = .task
        }
        .onReceive(NotificationCenter.default.publisher(for: .sageFocusAgentInput)) { note in
            guard note.object as? AgentSession.Kind == session.kind else { return }
            focusInputSoon()
            refreshGitBranch()
            updateWindowTitle()
        }
        .onChange(of: appState.isAgentWindowVisible) { _, visible in
            guard visible, appState.keySession.kind == session.kind else { return }
            focusInputSoon()
            refreshGitBranch()
            updateWindowTitle()
        }
        .onChange(of: session.agent.state.activeTaskID) { _, _ in
            stickToBottom = true
            focusInputSoon()
        }
        .onChange(of: session.agent.state.focusedProject?.id) { _, _ in
            projectTab = .task
            branchSwitchError = nil
            refreshGitBranch()
            updateWindowTitle()
        }
        .onChange(of: session.agent.state.didBootstrap) { _, ready in
            guard ready else { return }
            focusInputSoon()
            refreshGitBranch()
            updateWindowTitle()
        }
        .onChange(of: gitBranch) { _, _ in
            updateWindowTitle()
        }
        .onChange(of: projectTab) { _, tab in
            if tab == .task {
                focusInputSoon()
            }
        }
        .onChange(of: session.agent.state.phase) { _, phase in
            switch phase {
            case .awaitingConfirmation, .thinking, .executing:
                isInputFocused = false

            case .failed:
                isInputFocused = false

            case .idle, .completed:
                if projectTab == .task || !isProjectWindow {
                    focusInputSoon()
                }
            }
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var projectTabBody: some View {
        switch projectTab {
        case .task:
            taskPane

        case .files:
            if let root = session.agent.state.focusedProject?.rootURL {
                ProjectFilesBrowserView(rootURL: root)
                    .id("\(root.path)-\(gitBranch ?? "none")")
            }

        case .history:
            if let root = session.agent.state.focusedProject?.rootURL {
                ProjectHistoryBrowserView(rootURL: root)
                    // Refresh when branch changes after checkout.
                    .id(gitBranch ?? "none")
            }
        }
    }

    private var taskPane: some View {
        VStack(spacing: 0) {
            AgentTranscriptPane(
                stickToBottom: $stickToBottom
            ) { isInputFocused = false }
            Divider().opacity(SageDesign.Chrome.dividerOpacity)
            SkillTipsBanner()
                .animation(SageDesign.Motion.expandAnimation, value: session.skills.tips.showBanner)
            if let draft = session.skills.scriptScheduleDraft {
                ScheduleScriptPanel(initial: draft)
                    .id(draft.openedAt)
                    .transition(SkillTipChrome.bannerTransition)
            }
            AgentComposerView(
                isInputFocused: $isInputFocused,
                stickToBottom: $stickToBottom
            )
        }
        .animation(SageDesign.Motion.expandAnimation, value: session.skills.scriptScheduleDraft != nil)
    }

    private var bootstrapPlaceholder: some View {
        VStack(spacing: SageDesign.Spacing.medium) {
            ProgressView()
                .controlSize(.regular)
            Text(isProjectWindow ? "Opening project…" : "Starting Sage…")
                .font(.system(size: type.micro))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isProjectWindow ? "Opening project" : "Starting Sage")
    }

    private func branchErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: type.micro))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Dismiss") {
                branchSwitchError = nil
            }
            .controlSize(.mini)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.small)
        .background(Color.orange.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    private func refreshGitBranch() {
        guard let root = session.agent.state.focusedProject?.rootURL else {
            gitBranch = nil
            return
        }
        let url = root
        Task.detached(priority: .utility) {
            let branch = GitBranchReader.currentBranch(inProjectRoot: url)
            await MainActor.run { gitBranch = branch }
        }
    }

    /// Identity lives in the chrome strip (project name + branch). Keep the
    /// system titlebar text hidden so it doesn’t repeat the same information.
    private func updateWindowTitle() {
        let autosave = session.windowAutosaveName
        guard let window = NSApp.windows.first(where: { candidate in
            candidate.identifier?.rawValue == autosave
                || candidate.frameAutosaveName == autosave
        }) else { return }

        window.titleVisibility = .hidden
        window.representedURL = nil

        if session.isGeneral {
            window.title = "Sage"
            return
        }

        if let project = session.agent.state.focusedProject {
            // Still set for Window menu / Mission Control; not shown in the titlebar.
            window.title = project.name
        } else {
            window.title = "Opening…"
        }
    }

    private func focusInputSoon() {
        DispatchQueue.main.async {
            if session.agent.blocksNewInput { return }
            if case .failed = session.agent.state.phase, session.agent.canRetryFailure {
                isInputFocused = false
                return
            }
            if !session.agent.state.isBusy {
                isInputFocused = true
            }
        }
    }
}
