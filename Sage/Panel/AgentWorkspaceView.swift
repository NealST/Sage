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
    @FocusState private var isInputFocused: Bool
    @State private var stickToBottom = true
    @State private var gitBranch: String?

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            WorkspaceChromeView(
                onWillNavigate: {
                    stickToBottom = true
                    appState.clearDraft()
                },
                gitBranch: $gitBranch
            )
            if let hint = appState.agent.contextHint {
                contextChip(hint)
            }
            Divider().opacity(SageDesign.Chrome.dividerOpacity)
            transcript
            Divider().opacity(SageDesign.Chrome.dividerOpacity)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.pathGuardPolicy, appState.agent.pathGuardPolicy)
        .onAppear {
            focusInputSoon()
            refreshGitBranch()
            updateWindowTitle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sageFocusAgentInput)) { _ in
            focusInputSoon()
            refreshGitBranch()
            updateWindowTitle()
        }
        .onChange(of: appState.isAgentWindowVisible) { _, visible in
            if visible {
                focusInputSoon()
                refreshGitBranch()
                updateWindowTitle()
            }
        }
        .onChange(of: appState.agent.activeTaskID) { _, _ in
            stickToBottom = true
            focusInputSoon()
        }
        .onChange(of: appState.agent.focusedProject?.id) { _, _ in
            refreshGitBranch()
            updateWindowTitle()
        }
        .onChange(of: gitBranch) { _, _ in
            updateWindowTitle()
        }
        .onChange(of: appState.agent.phase) { _, phase in
            switch phase {
            case .awaitingConfirmation, .thinking, .executing:
                isInputFocused = false
            case .failed:
                isInputFocused = false
            default:
                focusInputSoon()
            }
        }
    }

    private func refreshGitBranch() {
        guard let root = appState.agent.focusedProject?.rootURL else {
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
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "SageAgentWindow"
                || $0.frameAutosaveName == "SageAgentWindow"
        }) else { return }

        if let project = appState.agent.focusedProject {
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
            // Avoid “Sage” stacked above Open / New in the unified strip.
            window.titleVisibility = .hidden
        }
    }

    private func contextChip(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .accessibilityHidden(true)
            Text(hint)
                .font(.system(size: SageDesign.Typography.microSize))
                .lineLimit(1)
                .accessibilityLabel(hint)
            Spacer(minLength: 4)
            Button("Don’t reuse") {
                appState.agent.dismissContextHint()
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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SageDesign.Spacing.md) {
                        if displayEvents.isEmpty {
                            emptyTranscript
                        }

                        ForEach(displayEvents) { event in
                            eventBubble(event)
                                .id(event.id)
                        }

                        phaseAccessory
                            .id("phase-accessory")
                    }
                    .padding(SageDesign.Spacing.lg)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let threshold: CGFloat = 72
                    return geometry.contentOffset.y + geometry.containerSize.height
                        >= geometry.contentSize.height - threshold
                } action: { _, nearBottom in
                    stickToBottom = nearBottom
                }
                .onChange(of: appState.agent.events.count) { _, _ in
                    guard stickToBottom else { return }
                    scrollToLatest(using: proxy)
                }
                .onChange(of: appState.agent.phase) { _, _ in
                    guard stickToBottom else { return }
                    scrollToLatest(using: proxy)
                }
                // Scroll during streaming — throttled by observing coarse content changes.
                // Triggers on new lines OR every ~80 characters (whichever comes first).
                .onChange(of: appState.agent.streamingText.scrollThrottleKey) { _, _ in
                    guard stickToBottom else { return }
                    scrollToLatestStreaming(using: proxy)
                }

                if !stickToBottom && !displayEvents.isEmpty {
                    Button {
                        stickToBottom = true
                        scrollToLatest(using: proxy)
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down")
                            .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.bottom, SageDesign.Spacing.md)
                    .accessibilityLabel("Jump to latest")
                }
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Text("Ask Sage to work on your Mac")
                .font(.system(size: SageDesign.Typography.titleSize, weight: .semibold))
            Text("Try “Summarize my Downloads folder” or “Rewrite what’s on my clipboard.”")
                .font(.system(size: SageDesign.Typography.bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(hotkeyHint)
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SageDesign.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var hotkeyHint: String {
        if appState.hotkeyRegistrationFailed {
            return "Open Sage from the menu bar when the global shortcut isn’t available."
        }
        return "Open anytime with ⌘⇧Space."
    }

    private var displayEvents: [AgentEvent] {
        appState.agent.events.filter { event in
            if event.kind == .toolResult { return true }
            if event.kind == .assistantResponse, event.toolCalls != nil {
                return true
            }
            return event.kind == .userInput || event.kind == .assistantResponse
        }
    }

    private func toolResultContent(for callID: String) -> String? {
        appState.agent.events.last(where: {
            $0.kind == .toolResult && $0.toolCallID == callID && !$0.content.hasPrefix("ERROR:")
        })?.content
    }

    /// Live disk preview only for proposed writes that have not executed yet.
    private func shouldPreviewToolCallAgainstDisk(callID: String) -> Bool {
        !appState.agent.events.contains(where: {
            $0.kind == .toolResult && $0.toolCallID == callID
        })
    }

    @ViewBuilder
    private var phaseAccessory: some View {
        switch appState.agent.phase {
        case .thinking:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                if appState.agent.isStreaming {
                    StreamingContentView(text: appState.agent.streamingText)
                        .transition(.opacity)
                } else {
                    HStack(spacing: SageDesign.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…")
                            .font(.system(size: SageDesign.Typography.bodySize))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                }
            }
            .animation(SageDesign.Motion.streamingTransition, value: appState.agent.isStreaming)
            // Stop button stays anchored outside the animated content — no position jump.
            .overlay(alignment: .topTrailing) {
                if appState.agent.canStop {
                    Button("Stop") {
                        appState.agent.stop()
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                }
            }

        case .awaitingConfirmation(let plan), .executing(let plan):
            PlanCardView(
                plan: plan,
                isExecuting: {
                    if case .executing = appState.agent.phase { return true }
                    return false
                }(),
                onConfirm: {
                    Task { await appState.agent.confirmPendingPlan() }
                },
                onCancel: {
                    Task { await appState.agent.cancelPendingPlan() }
                },
                onStop: {
                    appState.agent.stop()
                }
            )

        case .failed(let message):
            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SageDesign.Spacing.sm) {
                    if appState.agent.canRetryFailure {
                        Button("Retry") {
                            stickToBottom = true
                            Task { await appState.agent.retryLastFailure() }
                        }
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                        .disabled(appState.agent.isBusy)
                    }
                    if looksLikeConfigurationError(message) {
                        Button("Open Settings") {
                            NotificationCenter.default.post(name: .sageOpenSettings, object: nil)
                        }
                        .controlSize(.small)
                    }
                    Button("Dismiss") {
                        Task { await appState.agent.dismissFailure() }
                    }
                    .controlSize(.small)
                    .help(
                        appState.agent.hasPendingPlan
                            ? "Abandon the pending plan"
                            : "Dismiss this error"
                    )
                }
            }
            .onAppear { isInputFocused = false }

        case .idle, .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func eventBubble(_ event: AgentEvent) -> some View {
        switch event.kind {
        case .userInput:
            Text(event.content)
                .font(.system(size: SageDesign.Typography.inputSize))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .assistantResponse:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                if !event.content.isEmpty {
                    MarkdownContentView(markdown: event.content, collapsible: true)
                }
                if let calls = event.toolCalls, !calls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calls, id: \.id) { call in
                            ToolCallView(
                                name: call.name,
                                argumentsJSON: call.argumentsJSON,
                                resultContent: toolResultContent(for: call.id),
                                previewAgainstDisk: shouldPreviewToolCallAgainstDisk(callID: call.id)
                            )
                        }
                    }
                }
            }

        case .toolResult:
            ToolResultView(content: event.content)

        case .systemInstruction:
            EmptyView()
        }
    }

    private var composer: some View {
        @Bindable var appState = appState

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: SageDesign.Spacing.sm) {
                TextField(composerPlaceholder, text: $appState.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: SageDesign.Typography.inputSize))
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .disabled(blocksTyping)
                    .onSubmit {
                        guard !blocksSubmit else { return }
                        submit()
                    }
                    .accessibilityHint(composerAccessibilityHint)

                if !appState.draft.isEmpty && !blocksSubmit {
                    Text("Submit ⏎")
                        .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(
                            AccessibilityPreferences.increaseContrast
                                ? SageDesign.Chrome.strokeOpacity
                                : 0
                        ),
                        lineWidth: AccessibilityPreferences.increaseContrast ? 1 : 0
                    )
            }

            HStack {
                Text(appState.settings.model)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.tertiary)
                Spacer()
                if case .awaitingConfirmation = appState.agent.phase {
                    Label("Run or Cancel the pending plan", systemImage: SageDesign.Symbol.pending)
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.orange.opacity(0.95))
                        .labelStyle(.titleAndIcon)
                } else if appState.agent.canStop {
                    Button("Stop") {
                        appState.agent.stop()
                    }
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else if blocksTyping {
                    Text(
                        appState.agent.hasPendingPlan
                            ? "Resolve the pending plan first…"
                            : "Sage is working…"
                    )
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.md)
    }

    private var composerPlaceholder: String {
        if appState.agent.hasPendingPlan {
            return "Finish the pending plan first…"
        }
        if blocksTyping {
            return "Sage is working…"
        }
        return "Ask Sage…"
    }

    private var composerAccessibilityHint: String {
        if appState.agent.hasPendingPlan {
            return "Run, cancel, or retry the pending plan before sending"
        }
        if blocksTyping { return "Unavailable while Sage is working" }
        return "Press Return to send"
    }

    private var blocksTyping: Bool {
        appState.agent.blocksNewInput
    }

    private var blocksSubmit: Bool {
        blocksTyping
    }

    private func looksLikeConfigurationError(_ message: String) -> Bool {
        AppState.looksLikeConfigurationError(message, isConfigured: appState.settings.isConfigured)
    }

    private func submit() {
        let trimmed = appState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !blocksSubmit else { return }
        stickToBottom = true
        Task {
            let accepted = await appState.agent.submit(trimmed)
            if accepted {
                appState.clearDraft()
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        if let animation = SageDesign.Motion.scrollAnimation {
            withAnimation(animation) {
                proxy.scrollTo("phase-accessory", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("phase-accessory", anchor: .bottom)
        }
    }

    /// Streaming-specific scroll — uses a critically damped spring for smooth tracking.
    private func scrollToLatestStreaming(using proxy: ScrollViewProxy) {
        let animation = AccessibilityPreferences.reduceMotion
            ? nil : SageDesign.Motion.streamingScroll
        if let animation {
            withAnimation(animation) {
                proxy.scrollTo("phase-accessory", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("phase-accessory", anchor: .bottom)
        }
    }

    private func focusInputSoon() {
        DispatchQueue.main.async {
            if appState.agent.blocksNewInput { return }
            if case .failed = appState.agent.phase, appState.agent.canRetryFailure {
                // Keep focus off the composer so Return activates Retry.
                isInputFocused = false
                return
            }
            if !appState.agent.isBusy {
                isInputFocused = true
            }
        }
    }
}


// MARK: - Streaming scroll throttle

private extension String {
    /// Coarse key combining line count and length bucket — triggers scroll updates
    /// on new lines OR every ~80 characters, whichever comes first.
    /// This avoids per-character scroll while still tracking long unwrapped lines.
    var scrollThrottleKey: Int {
        var lines = 1
        for char in self where char == "\n" { lines += 1 }
        let lengthBucket = count / 80
        return lines &* 1000 &+ lengthBucket
    }
}
