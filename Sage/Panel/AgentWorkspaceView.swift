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
        session.agent.state.focusedProject != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceChromeView(
                gitBranch: $gitBranch,
                branchSwitchError: $branchSwitchError
            )

            if let branchSwitchError, !branchSwitchError.isEmpty {
                branchErrorBanner(branchSwitchError)
            }

            if let hint = session.agent.state.contextHint, projectTab == .task || !isProjectWindow {
                contextChip(hint)
            }

            if isProjectWindow {
                projectTabPicker
                Divider().opacity(SageDesign.Chrome.dividerOpacity)
                projectTabBody
            } else {
                Divider().opacity(SageDesign.Chrome.dividerOpacity)
                taskPane
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
            case .awaitingConfirmation, .awaitingSkillChoice, .thinking, .executing:
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

    private var projectTabPicker: some View {
        Picker("Workspace", selection: $projectTab) {
            ForEach(ProjectWorkspaceTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.sm)
        .accessibilityLabel("Workspace tabs")
    }

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
                stickToBottom: $stickToBottom,
                onFailureAppear: { isInputFocused = false }
            )
            Divider().opacity(SageDesign.Chrome.dividerOpacity)
            SkillTipsBanner()
                .animation(SageDesign.Motion.expandAnimation, value: session.skills.tips.showBanner)
            AgentComposerView(
                isInputFocused: $isInputFocused,
                stickToBottom: $stickToBottom
            )
        }
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
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.sm)
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

    /// Unify window chrome: General hides title (actions live in the strip);
    /// Project uses the system title + folder proxy for path / branch.
    private func updateWindowTitle() {
        let autosave = session.windowAutosaveName
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == autosave
                || $0.frameAutosaveName == autosave
        }) else { return }

        if let project = session.agent.state.focusedProject {
            window.titleVisibility = .visible
            window.representedURL = project.rootURL
            if let gitBranch, !gitBranch.isEmpty {
                window.title = "\(project.name) — \(gitBranch)"
            } else {
                window.title = project.name
            }
        } else {
            window.representedURL = nil
            window.title = "Sage"
            window.titleVisibility = .hidden
        }
    }

    private func contextChip(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: type.micro, weight: .semibold))
                .accessibilityHidden(true)
            Text(hint)
                .font(.system(size: type.micro))
                .lineLimit(1)
                .accessibilityLabel(hint)
            Spacer(minLength: 4)
            Button("Don’t reuse") {
                session.agent.dismissContextHint()
            }
            .controlSize(.mini)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Next request starts without this prior context")
            .accessibilityHint("Next request starts without this prior context")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.bottom, SageDesign.Spacing.sm)
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
