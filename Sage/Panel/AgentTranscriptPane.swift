//
//  AgentTranscriptPane.swift
//  Sage
//
//  Transcript + phase accessory. Isolated so streaming tokens do not rebuild
//  chrome / tips / composer.
//

import SwiftUI

/// O(n) index of tool results for bubble rendering (avoids per-bubble scans).
struct ToolResultIndex: Equatable {
    /// Successful (non-ERROR) tool results by call id.
    let successContentByCallID: [String: String]
    /// Call ids that already have any tool result (including errors).
    let completedCallIDs: Set<String>

    static let empty = Self(successContentByCallID: [:], completedCallIDs: [])

    init(successContentByCallID: [String: String], completedCallIDs: Set<String>) {
        self.successContentByCallID = successContentByCallID
        self.completedCallIDs = completedCallIDs
    }

    init(events: [AgentEvent]) {
        var success: [String: String] = [:]
        var completed = Set<String>()
        for event in events where event.kind == .toolResult {
            guard let callID = event.toolCallID else { continue }
            completed.insert(callID)
            if !event.content.hasPrefix("ERROR:") {
                success[callID] = event.content
            }
        }
        self.init(successContentByCallID: success, completedCallIDs: completed)
    }

    func successContent(for callID: String) -> String? {
        successContentByCallID[callID]
    }

    func shouldPreviewAgainstDisk(callID: String) -> Bool {
        !completedCallIDs.contains(callID)
    }
}

/// Cheap identity for transcript event lists — rebuild indexes only when this changes.
private struct TranscriptEventRevision: Equatable {
    let count: Int
    let lastID: UUID?
}

struct AgentTranscriptPane: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Binding var stickToBottom: Bool
    var onFailureAppear: () -> Void = {}

    @State private var eventRevision = TranscriptEventRevision(count: 0, lastID: nil)
    @State private var toolIndex = ToolResultIndex.empty
    @State private var displayEvents: [AgentEvent] = []

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                        if displayEvents.isEmpty {
                            emptyTranscript
                        }

                        ForEach(displayEvents) { event in
                            eventBubble(event, toolIndex: toolIndex)
                                .id(event.id)
                        }

                        phaseAccessory {
                                guard stickToBottom else { return }
                                scrollToLatestStreaming(using: proxy)
                        }
                        .id("phase-accessory")
                    }
                    .padding(SageDesign.Spacing.large)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let threshold: CGFloat = 72
                    return geometry.contentOffset.y + geometry.containerSize.height
                        >= geometry.contentSize.height - threshold
                } action: { _, nearBottom in
                    stickToBottom = nearBottom
                }
                .onAppear {
                    refreshTranscriptCachesIfNeeded()
                }
                .onChange(of: transcriptEventRevision) { _, _ in
                    refreshTranscriptCachesIfNeeded()
                    guard stickToBottom else { return }
                    scrollToLatest(using: proxy)
                }
                .onChange(of: session.agent.state.phase) { _, _ in
                    guard stickToBottom else { return }
                    scrollToLatest(using: proxy)
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
                    .padding(.bottom, SageDesign.Spacing.medium)
                    .accessibilityLabel("Jump to latest")
                }
            }
        }
    }

    private var transcriptEventRevision: TranscriptEventRevision {
        let events = session.agent.state.events
        return TranscriptEventRevision(count: events.count, lastID: events.last?.id)
    }

    private func refreshTranscriptCachesIfNeeded() {
        let revision = transcriptEventRevision
        guard revision != eventRevision else { return }
        let events = session.agent.state.events
        eventRevision = revision
        toolIndex = ToolResultIndex(events: events)
        displayEvents = events.filter { event in
            if event.kind == .toolResult { return true }
            if event.kind == .assistantResponse, event.toolCalls != nil {
                return true
            }
            return event.kind == .userInput || event.kind == .assistantResponse
        }
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if let project = session.agent.state.focusedProject {
                Text("Tell me what to do")
                    .font(.system(size: SageDesign.Typography.titleSize, weight: .semibold))
                Text("Sage can explore and edit files under \(ProjectPanelActions.displayPath(project.rootPath)).")
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SageDesign.Spacing.large)
        .accessibilityElement(children: .combine)
    }

    private var hotkeyHint: String {
        if appState.hotkeyRegistrationFailed {
            return "Open Sage from the menu bar when the global shortcut isn’t available."
        }
        return "Open anytime with ⌘⇧Space."
    }

    @ViewBuilder
    private func phaseAccessory(onStreamScroll: @escaping () -> Void) -> some View {
        switch session.agent.state.phase {
        case .thinking:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                if let todos = session.agent.state.activeTask?.todos, !todos.isEmpty {
                    TodoListCard(items: todos)
                }
                ThinkingStreamAccessory(
                    retryState: session.agent.state.retryState,
                    canStop: session.agent.canStop,
                    onStop: { session.agent.stop() },
                    onStreamScroll: onStreamScroll
                )
            }

        case .awaitingConfirmation, .executing:
            let isExecuting: Bool = {
                if case .executing = session.agent.state.phase { return true }
                return false
            }()
            VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                if let todos = session.agent.state.activeTask?.todos, !todos.isEmpty {
                    TodoListCard(items: todos)
                }
                switch session.agent.turnChrome {
                case .workPlan:
                    if let workPlan = session.agent.state.activeTask?.workPlan {
                        WorkPlanCard(
                            plan: workPlan,
                            isExecuting: isExecuting,
                            onConfirm: {
                                Task { await session.agent.confirmWorkPlan() }
                            },
                            onCancel: {
                                Task { await session.agent.cancelPendingPlan() }
                            },
                            onStop: {
                                session.agent.stop()
                            }
                        )
                    }

                case .toolBatch:
                    if let plan = session.agent.planProgress.plan
                        ?? session.agent.state.activeTask?.pendingPlan {
                        PlanCardView(
                            plan: plan,
                            isExecuting: isExecuting,
                            onConfirm: {
                                Task { await session.agent.confirmToolBatch() }
                            },
                            onCancel: {
                                Task { await session.agent.cancelPendingPlan() }
                            },
                            onStop: {
                                session.agent.stop()
                            }
                        )
                    }

                case .toolRoundLimit:
                    if case .toolRoundLimit(let current, let next) = session.agent.state.pendingPrompt {
                        ToolRoundLimitCard(
                            currentLimit: current,
                            nextLimit: next,
                            onContinue: {
                                Task { await session.agent.confirmToolRoundLimit() }
                            },
                            onFinish: {
                                Task { await session.agent.finishToolRoundLimit() }
                            }
                        )
                    }

                case .toolApproval:
                    if case .toolApproval(_, let name, let args, let title) = session.agent.state.pendingPrompt {
                        ToolApprovalCard(
                            title: title,
                            toolName: name,
                            argumentsJSON: args,
                            onAllowOnce: {
                                Task { await session.agent.confirmToolApproval(scope: .once) }
                            },
                            onAllowSession: {
                                Task { await session.agent.confirmToolApproval(scope: .session) }
                            },
                            onAllowTool: {
                                Task { await session.agent.confirmToolApproval(scope: .tool) }
                            },
                            onSkip: {
                                Task { await session.agent.skipToolApproval() }
                            }
                        )
                    }

                case .none:
                    EmptyView()
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SageDesign.Spacing.small) {
                    if session.agent.canRetryFailure {
                        Button("Retry") {
                            stickToBottom = true
                            Task { await session.agent.retryLastFailure() }
                        }
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                        .disabled(session.agent.state.isBusy)
                    }
                    if looksLikeConfigurationError(message) {
                        Button("Open Settings") {
                            NotificationCenter.default.post(name: .sageOpenSettings, object: nil)
                        }
                        .controlSize(.small)
                    }
                    Button("Dismiss") {
                        Task { await session.agent.dismissFailure() }
                    }
                    .controlSize(.small)
                    .help(
                        session.agent.state.hasPendingPlan
                            ? "Abandon the pending plan"
                            : "Dismiss this error"
                    )
                }
            }
            .onAppear(perform: onFailureAppear)

        case .idle, .completed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func eventBubble(_ event: AgentEvent, toolIndex: ToolResultIndex) -> some View {
        switch event.kind {
        case .userInput:
            Text(event.content)
                .font(.system(size: SageDesign.Typography.inputSize))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .assistantResponse:
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                if !event.content.isEmpty {
                    MarkdownContentView(markdown: event.content, collapsible: true)
                }
                if let calls = event.toolCalls, !calls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calls, id: \.id) { call in
                            ToolCallView(
                                name: call.name,
                                argumentsJSON: call.argumentsJSON,
                                titleOverride: Self.isSyntheticSkillLoad(call.id)
                                    ? "Loaded skill: \(ToolCallPresentation.extractArg(call.argumentsJSON, key: "name") ?? "…")"
                                    : nil,
                                resultContent: toolIndex.successContent(for: call.id),
                                previewAgainstDisk: toolIndex.shouldPreviewAgainstDisk(callID: call.id)
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

    private func looksLikeConfigurationError(_ message: String) -> Bool {
        AppState.looksLikeConfigurationError(message, isConfigured: appState.settings.isConfigured)
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

    private func scrollToLatestStreaming(using proxy: ScrollViewProxy) {
        let animation = AccessibilitySettings.shared.reduceMotion
            ? nil : SageDesign.Motion.streamingScroll
        if let animation {
            withAnimation(animation) {
                proxy.scrollTo("phase-accessory", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("phase-accessory", anchor: .bottom)
        }
    }

    /// Slash / explicit `load_skill` events (legacy `auto_skill_` ids still match).
    private static func isSyntheticSkillLoad(_ callID: String) -> Bool {
        callID.hasPrefix("skill_load_") || callID.hasPrefix("auto_skill_")
    }
}

// MARK: - Thinking + streaming (isolated observation)

/// Owns `StreamingPlayback` reads so event bubbles do not rebuild on SSE tokens.
private struct ThinkingStreamAccessory: View {
    @Environment(StreamingPlayback.self) private var streaming
    let retryState: RetryDisplayState?
    let canStop: Bool
    let onStop: () -> Void
    let onStreamScroll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if streaming.isActive {
                StreamingContentView(text: streaming.text)
                    .transition(.opacity)
            } else if let retry = retryState {
                RetryCountdownView(state: retry)
                    .transition(.opacity)
            } else {
                HStack(spacing: SageDesign.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…")
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
        .animation(SageDesign.Motion.streamingTransition, value: streaming.isActive)
        .overlay(alignment: .topTrailing) {
            if canStop {
                Button("Stop", action: onStop)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .onChange(of: streaming.scrollThrottleKey) { _, _ in
            onStreamScroll()
        }
    }
}

// MARK: - Streaming scroll throttle (legacy helper removed — key lives on StreamingPlayback)
