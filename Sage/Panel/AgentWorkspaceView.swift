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
    @State private var gitBranches: [String] = []
    @State private var branchSwitchError: String?
    @State private var projectTab: ProjectWorkspaceTab = .task

    private var isProjectWindow: Bool {
        !session.isGeneral
    }

    private var isWorkspaceReady: Bool {
        session.agent.state.didBootstrap
    }

    var body: some View {
        // No SwiftUI canvas paint: the window body IS the system Liquid Glass
        // material, and painting `Color(.windowBackgroundColor)` here renders
        // as a flat graphite slab (rgb 30,30,30) that clashes with the glass
        // frame and chrome. Transparent content lets the material show.
        VStack(spacing: 0) {
            workspaceCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isWorkspaceReady, showsTaskPane {
                bottomChrome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The toolbar chrome owns the titlebar band itself — one row on the
        // traffic-light centerline — and the canvas scrolls under it with the
        // system soft edge effect, the way native Liquid Glass toolbars work.
        // Order matters: the inset places the chrome at the top of the canvas,
        // and ignoring the container's top safe area afterwards extends the
        // canvas (with its inset) up into the titlebar band.
        .safeAreaInset(edge: .top, spacing: 0) {
            topChrome
        }
        .ignoresSafeArea(.container, edges: .top)
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
        .onReceive(NotificationCenter.default.publisher(for: .sageSelectWorkspaceTab)) { note in
            guard note.object as? AgentSession.Kind == session.kind else { return }
            guard isProjectWindow,
                  let raw = note.userInfo?[ProjectWorkspaceTab.notificationKey] as? String,
                  let tab = ProjectWorkspaceTab(rawValue: raw)
            else { return }
            projectTab = tab
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
            case .awaitingConfirmation, .thinking, .executing, .failed:
                isInputFocused = false

            case .idle, .completed:
                // Stay put so the user can select and copy the reply.
                break
            }
            appState.refreshDockBadge()
            requestAttentionIfNeeded(phase)
        }
    }

    // MARK: - Tabs

    private var showsTaskPane: Bool {
        projectTab == .task || !isProjectWindow
    }

    @ViewBuilder private var workspaceCanvas: some View {
        if isWorkspaceReady {
            if isProjectWindow {
                projectTabBody
            } else {
                taskScrollSurface
            }
        } else {
            bootstrapPlaceholder
        }
    }

    @ViewBuilder private var topChrome: some View {
        // Floating glass chrome over the system toolbar band — unpainted, so
        // the window's Liquid Glass material carries the strip and the canvas
        // scrolls under it with the soft edge fade. The container blends
        // neighboring chips when the window narrows.
        GlassEffectContainer(spacing: SageDesign.Spacing.extraSmall) {
            VStack(spacing: 0) {
                WorkspaceChromeView(
                    gitBranch: $gitBranch,
                    gitBranches: $gitBranches,
                    branchSwitchError: $branchSwitchError,
                    projectTab: $projectTab
                )
                if let branchSwitchError, !branchSwitchError.isEmpty {
                    branchErrorBanner(branchSwitchError)
                }
                if isWorkspaceReady, showsTaskPane {
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
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bottomChrome: some View {
        GlassEffectContainer(spacing: SageDesign.Glass.containerSpacing) {
            VStack(spacing: 0) {
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
        }
        .animation(SageDesign.Motion.expandAnimation, value: session.skills.scriptScheduleDraft != nil)
    }

    @ViewBuilder private var projectTabBody: some View {
        switch projectTab {
        case .task:
            taskScrollSurface

        case .files:
            if let root = session.agent.state.focusedProject?.rootURL {
                ProjectFilesBrowserView(rootURL: root)
                    .id("\(root.path)-\(gitBranch ?? "none")")
                    .sageScrollEdgeGlass()
            } else {
                ContentUnavailableView {
                    Label("No Project", systemImage: "folder")
                } description: {
                    Text("Open a project to browse its files.")
                }
            }

        case .history:
            if let root = session.agent.state.focusedProject?.rootURL {
                VStack(spacing: 0) {
                    SageTasksSection(repository: appState.taskRepository, projectID: session.projectID)
                    Divider()
                    ProjectHistoryBrowserView(rootURL: root, branch: gitBranch)
                        .id(gitBranch ?? "none")
                        .sageScrollEdgeGlass()
                }
            } else {
                // General window: no git history to show — task history is the page.
                TaskHistoryBrowserView(
                    repository: appState.taskRepository,
                    projectID: nil
                )
                .sageScrollEdgeGlass()
            }
        }
    }

    private var taskScrollSurface: some View {
        AgentTranscriptPane(
            stickToBottom: $stickToBottom,
            composerFocused: isInputFocused
        ) {
            isInputFocused = false
        }
    }

    private var bootstrapPlaceholder: some View {
        TranscriptBootstrapSkeleton(isProjectWindow: isProjectWindow)
    }

    private func branchErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SageDesign.Palette.warning)
                .accessibilityHidden(true)
            Text(message)
                .sageMicro(type.micro)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: SageDesign.Spacing.extraSmall)
            Button("Dismiss") {
                branchSwitchError = nil
            }
            .sageGlassButton()
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.bottom, SageDesign.Spacing.small)
        .accessibilityElement(children: .combine)
    }

    private func refreshGitBranch() {
        guard let root = session.agent.state.focusedProject?.rootURL else {
            gitBranch = nil
            gitBranches = []
            return
        }
        let url = root
        Task.detached(priority: .utility) {
            // One detached pass fetches both — the branch menu must never run
            // `git branch` (a blocking subprocess) on the main thread.
            let branch = GitBranchReader.currentBranch(inProjectRoot: url)
            let branches = GitBranchReader.localBranches(inProjectRoot: url)
            await MainActor.run {
                gitBranch = branch
                gitBranches = branches
            }
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
            isInputFocused = true
        }
    }

    /// One attention signal per phase transition while the user's attention
    /// is elsewhere. Channels split by Apple's feedback kinds: decisions need
    /// a chime (the deadlock case — the agent waits on the user while the
    /// user thinks Sage is working) plus a banner, the visible channel a Dock
    /// bounce can't reach (fullscreen, another Space, hidden Dock);
    /// completed/failed lean on their system notification banner (which
    /// carries its own sound) plus the Dock bounce, so no second sound stacks
    /// on top. App activation is too coarse — the user focused in Settings
    /// or another project's window still needs the signal for this
    /// transcript.
    private func requestAttentionIfNeeded(_ phase: AgentPhase) {
        switch phase {
        case .awaitingConfirmation:
            guard appState.windowControllers[session.kind]?.isKey != true else { return }
            NSSound(named: NSSound.Name("Ping"))?.play()
            NSApp.requestUserAttention(.informationalRequest)
            postApprovalAttentionBanner()

        case .failed, .completed, .thinking, .executing, .idle:
            // A phase change away from awaitingConfirmation means the
            // decision is made — retire the banner wherever it still sits.
            TaskCompletionNotifier.clearApprovalAttention(projectID: session.projectID)
            guard appState.windowControllers[session.kind]?.isKey != true else { return }
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    private func postApprovalAttentionBanner() {
        let scope = session.agent.state.focusedProject?.name ?? "Sage"
        TaskCompletionNotifier.postApprovalAttention(
            ApprovalAttentionPayload(
                projectID: session.projectID,
                title: "\(scope) · waiting for you",
                body: approvalAttentionBody
            )
        )
    }

    /// Plain-language restatement of what is pending. It names the *kind* of
    /// decision, never enough detail to act on inline — Allow/Skip happens
    /// in the transcript on unclipped arguments.
    private var approvalAttentionBody: String {
        switch session.agent.turnChrome {
        case .toolApproval: return "Sage needs approval to run a tool."
        case .toolRoundLimit: return "Sage reached a tool-round limit."
        case .reviewFailed: return "A review failed and needs a decision."
        case .reviewMustFix: return "A review wants the reply fixed."
        case .reviewOptional: return "A review suggested improvements."
        case .workPlan, .toolBatch, nil: return "A plan is ready for your decision."
        }
    }
}

/// Placeholder rows shaped like the transcript they become — the window's
/// structure lands instantly instead of a spinner floating in a void.
/// Quiet by design: one slow opacity pulse, dropped entirely under
/// Reduce Motion.
private struct TranscriptBootstrapSkeleton: View {
    let isProjectWindow: Bool
    @Environment(\.sageTypography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
            Text(isProjectWindow ? "Opening project…" : "Starting Sage…")
                .sageMicro(type.micro)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                bar(width: 210, height: 32)
                bar(width: 280, height: 14)
                bar(width: 240, height: 14)
                bar(width: 320, height: 64, radius: SageDesign.Glass.card)
                bar(width: 200, height: 14)
                bar(width: 150, height: 14)
            }
            .opacity(pulsing ? 0.45 : 0.8)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: pulsing
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.top, SageDesign.Spacing.small)
        .padding(.bottom, SageDesign.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard !reduceMotion else { return }
            pulsing = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isProjectWindow ? "Opening project" : "Starting Sage")
    }

    private func bar(width: CGFloat, height: CGFloat, radius: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: radius ?? height / 2, style: .continuous)
            .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}
