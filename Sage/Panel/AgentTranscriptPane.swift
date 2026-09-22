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
    /// Every tool result body, including errors — shown inside the call chip.
    let contentByCallID: [String: String]
    /// Call ids that already have any tool result (including errors).
    let completedCallIDs: Set<String>

    static let empty = Self(
        successContentByCallID: [:],
        contentByCallID: [:],
        completedCallIDs: []
    )

    init(
        successContentByCallID: [String: String],
        contentByCallID: [String: String],
        completedCallIDs: Set<String>
    ) {
        self.successContentByCallID = successContentByCallID
        self.contentByCallID = contentByCallID
        self.completedCallIDs = completedCallIDs
    }

    init(events: [AgentEvent]) {
        var success: [String: String] = [:]
        var content: [String: String] = [:]
        var completed = Set<String>()
        for event in events where event.kind == .toolResult {
            guard let callID = event.toolCallID else { continue }
            completed.insert(callID)
            content[callID] = event.content
            if !event.content.hasPrefix("ERROR:") {
                success[callID] = event.content
            }
        }
        self.init(
            successContentByCallID: success,
            contentByCallID: content,
            completedCallIDs: completed
        )
    }

    func successContent(for callID: String) -> String? {
        successContentByCallID[callID]
    }

    func content(for callID: String) -> String? {
        contentByCallID[callID]
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
    /// In-task find (⌘F). While active, the transcript dims non-matching
    /// events and keeps everything on screen.
    @State private var isFinding = false
    @State private var findText = ""
    @FocusState private var findFieldFocused: Bool
    /// Index into `findMatches`; ⌘G / ⇧⌘G step through, the bar shows "n of m".
    @State private var currentMatchIndex = 0
    /// Jump-to-latest sets `stickToBottom` before the scroll lands. Ignore
    /// the still-large distance-from-bottom so geometry doesn't unstick it.
    @State var isJumpingToLatest = false

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                        LazyVStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
                            if isSearching, findMatches.isEmpty {
                                noFindMatches
                            } else if displayEvents.isEmpty {
                                emptyTranscript
                            }

                            ForEach(displayEvents) { event in
                                eventBubble(event, toolIndex: toolIndex, scrollProxy: proxy)
                                    .id(event.id)
                                    .opacity(searchDim(event) ? SageDesign.Chrome.dimmedContentOpacity : 1)
                                    .allowsHitTesting(!searchDim(event))
                            }
                        }

                        if !isFinding {
                            phaseAccessory {
                                guard stickToBottom else { return }
                                scrollToLatestStreaming(using: proxy)
                            }
                            .id("phase-accessory")
                            .transition(SageDesign.Glass.appearTransition)
                        }

                        // Always in the tree (not inside LazyVStack) so Jump to
                        // latest can find it after the user has scrolled up.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.transcriptEndID)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, SageDesign.Spacing.large)
                    .padding(.top, SageDesign.Spacing.small)
                    .padding(.bottom, SageDesign.Spacing.large)
                    // Reading measure — content column stops at a comfortable
                    // line length instead of stretching with the window.
                    .frame(
                        maxWidth: SageDesign.Panel.readingColumnWidth,
                        alignment: .leading
                    )
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
                    // Find-bar mount/unmount settles; per-keystroke dimming is
                    // deliberately unanimated — a 0.3s spring on every keypress
                    // lags the query and interrupts streaming mid-flight.
                    .animation(SageDesign.Motion.expandAnimation, value: isFinding)
                }
                // Top edge fades under the floating toolbar chrome; bottom
                // fades under the composer's glass panel.
                .sageScrollEdgeGlass(edges: .bottom)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isFinding {
                        findBar(proxy: proxy)
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
                        if !isJumpingToLatest, distanceFromBottom > unstickThreshold {
                            stickToBottom = false
                        }
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
                .onChange(of: findText) { _, _ in
                    currentMatchIndex = 0
                    guard let first = findMatches.first else { return }
                    scrollToMatch(first.id, using: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: .sageFindInTranscript)) { note in
                    guard note.object as? AgentSession.Kind == session.kind else { return }
                    isFinding = true
                    currentMatchIndex = 0
                    findFieldFocused = true
                }

                if !stickToBottom && !displayEvents.isEmpty && !isFinding {
                    Button {
                        jumpToLatest(using: proxy)
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down")
                    }
                    .sageGlassButton(.large)
                    // End (Fn+→) — the scroll-to-bottom convention. ⌘↓ is
                    // taken by the composer's input-history recall.
                    .keyboardShortcut(.init("\u{F72B}"), modifiers: [])
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

    /// Find keeps every event on screen and dims the non-matching ones — a
    /// hit stays in context with the turns around it instead of the
    /// transcript collapsing to just the matches.
    var findMatches: [AgentEvent] {
        guard isSearching else { return [] }
        let query = findText.lowercased()
        return displayEvents.filter { matchesQuery($0, query: query) }
    }

    private var isSearching: Bool {
        isFinding && !findText.isEmpty
    }

    private func matchesQuery(_ event: AgentEvent, query: String) -> Bool {
        if event.content.lowercased().contains(query) { return true }
        return event.toolCalls?.contains { call in
            call.name.lowercased().contains(query)
                || call.argumentsJSON.lowercased().contains(query)
                || (toolIndex.content(for: call.id)?.lowercased().contains(query) ?? false)
        } ?? false
    }

    private func searchDim(_ event: AgentEvent) -> Bool {
        guard isSearching else { return false }
        return !matchesQuery(event, query: findText.lowercased())
    }

    private var matchCounterLabel: String {
        let count = findMatches.count
        guard count > 0 else { return "0 matches" }
        return "\(min(currentMatchIndex, count - 1) + 1) of \(count)"
    }

    private func stepMatch(_ delta: Int, using proxy: ScrollViewProxy) {
        let matches = findMatches
        guard !matches.isEmpty else { return }
        let count = matches.count
        let clamped = min(currentMatchIndex, count - 1)
        currentMatchIndex = (clamped + delta + count) % count
        scrollToMatch(matches[currentMatchIndex].id, using: proxy)
    }

    private func scrollToMatch(_ id: UUID, using proxy: ScrollViewProxy) {
        if let animation = SageDesign.Motion.streamingScroll {
            withAnimation(animation) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func findBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .sageFont(type.caption)
                .foregroundStyle(.tertiary)
            TextField("Find in task", text: $findText)
                .sageFont(type.body)
                .textFieldStyle(.plain)
                .focused($findFieldFocused)
            if isSearching {
                Text(matchCounterLabel)
                    .sageMicro(type.micro)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Button {
                    stepMatch(-1, using: proxy)
                } label: {
                    Image(systemName: "chevron.up")
                        .sageFont(type.caption)
                        .frame(
                            width: SageDesign.Control.iconButtonCompact,
                            height: SageDesign.Control.iconButtonCompact
                        )
                        .sageHitSlop(visualSize: SageDesign.Control.iconButtonCompact)
                }
                .buttonStyle(.plain)
                .disabled(findMatches.isEmpty)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .accessibilityLabel("Previous match")
                Button {
                    stepMatch(1, using: proxy)
                } label: {
                    Image(systemName: "chevron.down")
                        .sageFont(type.caption)
                        .frame(
                            width: SageDesign.Control.iconButtonCompact,
                            height: SageDesign.Control.iconButtonCompact
                        )
                        .sageHitSlop(visualSize: SageDesign.Control.iconButtonCompact)
                }
                .buttonStyle(.plain)
                .disabled(findMatches.isEmpty)
                .keyboardShortcut("g", modifiers: .command)
                .accessibilityLabel("Next match")
            }
            SageDismissButton(
                action: endFinding,
                label: "Close find",
                help: "Close find (Esc)"
            )
        }
        .padding(.horizontal, SageDesign.Spacing.medium)
        .padding(.vertical, SageDesign.Spacing.compactChipVertical)
        .background(
            RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
        )
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
        let attachedCallIDs = Set(events.flatMap { $0.toolCalls?.map(\.id) ?? [] })
        displayEvents = events.filter { event in
            if event.kind == .toolResult {
                // Results that belong to a tool-call chip render inside it
                // when expanded — not as a second row of first-line titles.
                if let callID = event.toolCallID, attachedCallIDs.contains(callID) {
                    return false
                }
                return true
            }
            return event.kind == .userInput || event.kind == .assistantResponse
        }
    }

    var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
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
            }
            VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
                if session.agent.state.focusedProject == nil {
                    Text(hotkeyHint)
                        .sageMicro(type.micro, weight: .medium)
                        .foregroundStyle(.secondary)
                }
                Text("Drop files, paste a screenshot, or press ⌘U to attach.")
                    .sageMicro(type.micro, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Label(starter.prompt, systemImage: starter.icon)
                }
                .sageGlassButton()
                .accessibilityHint("Fills the message box with this prompt")
            }
        }
    }

    var hotkeyHint: String {
        if appState.hotkeyRegistrationFailed {
            return "Open Sage from the menu bar when the global shortcut isn’t available."
        }
        return "Open anytime with \(appState.globalHotkey.symbolRepresentation)."
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
                .transition(SageDesign.Motion.streamingPhase)
            }
            if !streaming.thinking.isEmpty {
                ThinkingProcessView(
                    text: streaming.thinking,
                    replyStarted: !streaming.text.isEmpty
                )
                .transition(SageDesign.Motion.streamingPhase)
            }
            if !streaming.text.isEmpty {
                // Streaming always renders uncollapsed (block-cached + throttled).
                // Collapsing is a committed-reply affordance only — the reset in
                // MarkdownContentView's onChange would tear down its measure
                // cache every ~100ms and fight the user's expand choice.
                StreamingContentView(text: streaming.text)
                    .transition(SageDesign.Motion.streamingPhase)
            } else if status == nil, streaming.thinking.isEmpty, !streaming.isReservingWorkPlan {
                if let retry = retryState {
                    RetryCountdownView(
                        state: retry,
                        onStop: agentCanStop ? { onAgentStop() } : nil,
                        onRetryNow: onRetryNow
                    )
                    .transition(SageDesign.Motion.streamingPhase)
                } else {
                    HStack(spacing: SageDesign.Spacing.small) {
                        ProgressView().controlSize(.small)
                        Text(thinkingLabel)
                            .sageFont(type.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .transition(SageDesign.Motion.streamingPhase)
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
    /// read as progress instead of a frozen spinner. Same formatter as the
    /// chrome's Working badge.
    private var thinkingLabel: String {
        SageDesign.Elapsed.label(thinkingElapsedSeconds).map { "Thinking… \($0)" }
            ?? "Thinking…"
    }
}

// MARK: - Streaming scroll throttle (legacy helper removed — key lives on StreamingPlayback)
