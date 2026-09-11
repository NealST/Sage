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

    /// Transcript chips derive status from indexed results: no result yet means
    /// running while the turn is active, skipped once the turn ended without
    /// one landing (the call was dropped, not still queued).
    func status(for callID: String, isBusy: Bool) -> StepStatus {
        if successContentByCallID[callID] != nil { return .succeeded }
        if completedCallIDs.contains(callID) { return .failed }
        return isBusy ? .running : .skipped
    }
}

/// Cheap identity for transcript event lists — rebuild indexes only when this changes.
struct TranscriptEventRevision: Equatable {
    let count: Int
    let lastID: UUID?
}

struct AgentTranscriptPane: View {
    @Environment(AppState.self) var appState
    @Environment(AgentSession.self) var session
    @Environment(\.sageTypography) var type
    @Binding var stickToBottom: Bool
    /// When the composer has focus, confirmation cards must not steal Return.
    var composerFocused: Bool = false
    /// Mouse-down in the transcript — release composer focus so text selection can take first responder.
    var onBeginReading: () -> Void = {}

    @State private var eventRevision = TranscriptEventRevision(count: 0, lastID: nil)
    @State private var toolIndex = ToolResultIndex.empty
    /// Shared with the bubbles extension file (identity for latest-reply logic).
    @State var displayEvents: [AgentEvent] = []
    /// Matches the plan skeleton → confirmed plan card glass morph.
    @Namespace var planGlassNamespace
    /// In-task find (⌘F). While active, the transcript filters to matching events.
    @State private var isFinding = false
    @State private var findText = ""
    @FocusState private var findFieldFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                        if isFinding, !findText.isEmpty, visibleEvents.isEmpty {
                            noFindMatches
                        } else if displayEvents.isEmpty {
                            emptyTranscript
                        }

                        ForEach(visibleEvents) { event in
                            eventBubble(event, toolIndex: toolIndex)
                                .id(event.id)
                        }

                        if !isFinding {
                            phaseAccessory {
                                    guard stickToBottom else { return }
                                    scrollToLatestStreaming(using: proxy)
                            }
                            .id("phase-accessory")
                            .transition(SageDesign.Glass.appearTransition)
                        }
                    }
                    .padding(SageDesign.Spacing.large)
                    .animation(
                        SageDesign.Motion.expandAnimation,
                        value: session.agent.state.phase
                    )
                    .animation(
                        SageDesign.Motion.expandAnimation,
                        value: session.agent.turnChrome
                    )
                    // Todo insertions / status flips resize the accessory cards;
                    // settle those with the same spring as the phase changes.
                    .animation(
                        SageDesign.Motion.expandAnimation,
                        value: session.agent.state.activeTask?.todos
                    )
                }
                .sageScrollEdgeGlass()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isFinding {
                        findBar
                            .transition(SageDesign.Glass.appearTransition)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in onBeginReading() }
                )
                // Hysteresis: a wider window to re-stick than to un-stick, so
                // slow scrolling around the threshold doesn't flicker the
                // jump button in and out.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height
                        - geometry.contentOffset.y
                        - geometry.containerSize.height
                } action: { _, distanceFromBottom in
                    let stickThreshold: CGFloat = 72
                    let unstickThreshold: CGFloat = 96
                    if stickToBottom {
                        if distanceFromBottom > unstickThreshold { stickToBottom = false }
                    } else {
                        if distanceFromBottom <= stickThreshold { stickToBottom = true }
                    }
                }
                .onAppear {
                    refreshTranscriptCachesIfNeeded()
                }
                .onChange(of: transcriptEventRevision) { _, _ in
                    refreshTranscriptCachesIfNeeded()
                    guard stickToBottom, !isFinding else { return }
                    scrollToLatest(using: proxy)
                }
                .onChange(of: session.agent.state.phase) { _, _ in
                    guard stickToBottom, !isFinding else { return }
                    scrollToLatest(using: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sageFindInTranscript)) { note in
                    guard note.object as? AgentSession.Kind == session.kind else { return }
                    isFinding = true
                    findFieldFocused = true
                }

                if !stickToBottom && !displayEvents.isEmpty && !isFinding {
                    Button {
                        stickToBottom = true
                        scrollToLatest(using: proxy)
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down")
                            .sageMicro(type.micro, weight: .semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                    // Quiet glass, not prominent — a tertiary navigation control
                    // must not carry the same weight as Send / Allow.
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.bottom, SageDesign.Spacing.medium)
                    .transition(SageDesign.Glass.appearTransition)
                    .accessibilityLabel("Jump to latest")
                }
            }
            .animation(SageDesign.Motion.scrollAnimation, value: stickToBottom)
        }
    }

    var transcriptEventRevision: TranscriptEventRevision {
        let events = session.agent.state.events
        return TranscriptEventRevision(count: events.count, lastID: events.last?.id)
    }

    /// Find mode narrows the transcript to matching events — including their
    /// tool chips, so a search for a tool name or argument still finds the turn.
    var visibleEvents: [AgentEvent] {
        guard isFinding, !findText.isEmpty else { return displayEvents }
        let query = findText.lowercased()
        return displayEvents.filter { event in
            if event.content.lowercased().contains(query) { return true }
            return event.toolCalls?.contains { call in
                call.name.lowercased().contains(query)
                    || call.argumentsJSON.lowercased().contains(query)
            } ?? false
        }
    }

    private var findMatchLabel: String {
        let count = visibleEvents.count
        return count == 1 ? "1 match" : "\(count) matches"
    }

    private var findBar: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .sageFont(type.caption)
                .foregroundStyle(.tertiary)
            TextField("Find in task", text: $findText)
                .sageFont(type.body)
                .textFieldStyle(.plain)
                .focused($findFieldFocused)
            if isFinding, !findText.isEmpty {
                Text(findMatchLabel)
                    .sageMicro(type.micro)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Button {
                endFinding()
            } label: {
                Image(systemName: "xmark")
                    .sageFont(type.caption)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close find (Esc)")
            .accessibilityLabel("Close find")
        }
        .padding(.horizontal, SageDesign.Spacing.medium)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(SageDesign.Chrome.dividerOpacity))
                .frame(height: 1)
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.top, SageDesign.Spacing.small)
        .onKeyPress(.escape) {
            if findText.isEmpty {
                endFinding()
            } else {
                findText = ""
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find in task")
    }

    private var noFindMatches: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .sageFont(type.caption)
                .foregroundStyle(.secondary)
            Text("No matches for “\(findText)”")
                .sageFont(type.body)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, SageDesign.Spacing.large)
        .accessibilityElement(children: .combine)
    }

    private func endFinding() {
        isFinding = false
        findText = ""
        findFieldFocused = false
    }

    func refreshTranscriptCachesIfNeeded() {
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

    var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if let project = session.agent.state.focusedProject {
                Text("Tell me what to do")
                    .sageFont(type.title, weight: .semibold)
                Text("Sage can explore and edit files under \(ProjectPanelActions.displayPath(project.rootPath)).")
                    .sageFont(type.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Ask Sage to work on your Mac")
                    .sageFont(type.title, weight: .semibold)
                starterPromptChips
                Text(hotkeyHint)
                    .sageMicro(type.micro, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            Text("Drop files, paste a screenshot, or press ⇧⌘A to attach.")
                .sageMicro(type.micro, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SageDesign.Spacing.large)
        .accessibilityElement(children: .combine)
    }

    /// First-run prompts: one tap fills the composer (no auto-send — the user
    /// reviews, then hits Return), so the empty state is a door, not a dead end.
    private var starterPrompts: [(icon: String, prompt: String)] {
        [
            ("tray.full", "Summarize my Downloads folder"),
            ("doc.on.clipboard", "Rewrite what’s on my clipboard"),
        ]
    }

    private var starterPromptChips: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            ForEach(starterPrompts, id: \.prompt) { starter in
                Button {
                    session.draft = starter.prompt
                    NotificationCenter.default.post(
                        name: .sageFocusAgentInput,
                        object: session.kind
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: starter.icon)
                            .sageFont(type.caption)
                            .foregroundStyle(.secondary)
                        Text(starter.prompt)
                            .sageFont(type.body, weight: .medium)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(SagePressableChipButtonStyle())
                .accessibilityHint("Fills the message box with this prompt")
            }
        }
    }

    var hotkeyHint: String {
        if appState.hotkeyRegistrationFailed {
            return "Open Sage from the menu bar when the global shortcut isn’t available."
        }
        return "Open anytime with ⌘⇧Space."
    }
}

// MARK: - Thinking + streaming (isolated observation)

/// Owns `StreamingPlayback` reads so event bubbles do not rebuild on SSE tokens.
struct ThinkingStreamAccessory: View {
    @Environment(StreamingPlayback.self) private var streaming
    @Environment(\.sageTypography) private var type
    let retryState: RetryDisplayState?
    let onStreamScroll: () -> Void
    var status: String? = nil
    /// Namespace for the skeleton → confirmed plan card glass morph.
    var planGlassNamespace: Namespace.ID? = nil
    /// Stop affordance for the retry countdown — the wait is cancellable.
    var agentCanStop: Bool = false
    var onAgentStop: () -> Void = {}
    /// Skips the remaining retry backoff; nil hides the affordance.
    var onRetryNow: (() -> Void)? = nil
    @State private var thinkingElapsedSeconds = 0

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if let status {
                HStack(spacing: SageDesign.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .sageFont(type.body)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityLabel(status)
                .transition(.opacity)
            }
            if !streaming.thinking.isEmpty {
                ThinkingProcessView(
                    text: streaming.thinking,
                    replyStarted: !streaming.text.isEmpty
                )
                .transition(.opacity)
            }
            if !streaming.text.isEmpty {
                // Streaming always renders uncollapsed (block-cached + throttled).
                // Collapsing is a committed-reply affordance only — the reset in
                // MarkdownContentView's onChange would tear down its measure
                // cache every ~100ms and fight the user's expand choice.
                StreamingContentView(text: streaming.text)
                    .transition(.opacity)
            } else if status == nil, streaming.thinking.isEmpty, !streaming.isReservingWorkPlan {
                if let retry = retryState {
                    RetryCountdownView(
                        state: retry,
                        onStop: agentCanStop ? { onAgentStop() } : nil,
                        onRetryNow: onRetryNow
                    )
                    .transition(.opacity)
                } else {
                    HStack(spacing: SageDesign.Spacing.small) {
                        ProgressView().controlSize(.small)
                        Text(thinkingLabel)
                            .sageFont(type.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                }
            }
            if streaming.isReservingWorkPlan {
                WorkPlanCardSkeleton(
                    matchedGlass: planGlassNamespace.map {
                        SageDesign.Glass.MatchedSpec(
                            id: SageDesign.Glass.workPlanCardMatchID,
                            namespace: $0
                        )
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(SageDesign.Motion.streamingTransition, value: streaming.isActive)
        .animation(SageDesign.Motion.streamingTransition, value: streaming.isReservingWorkPlan)
        .task(id: showsPlainThinkingSpinner) {
            guard showsPlainThinkingSpinner else { return }
            thinkingElapsedSeconds = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                thinkingElapsedSeconds += 1
            }
        }
        .onChange(of: streaming.scrollThrottleKey) { _, _ in
            onStreamScroll()
        }
    }

    private var showsPlainThinkingSpinner: Bool {
        retryState == nil
            && status == nil
            && streaming.thinking.isEmpty
            && streaming.text.isEmpty
            && !streaming.isReservingWorkPlan
    }

    /// Silence for the first few seconds, then an elapsed count so long waits
    /// read as progress instead of a frozen spinner.
    private var thinkingLabel: String {
        thinkingElapsedSeconds >= 5 ? "Thinking… \(thinkingElapsedSeconds)s" : "Thinking…"
    }
}

// MARK: - Streaming scroll throttle (legacy helper removed — key lives on StreamingPlayback)
