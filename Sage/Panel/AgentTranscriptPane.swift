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
struct TranscriptEventRevision: Equatable {
    let count: Int
    let lastID: UUID?
}

struct AgentTranscriptPane: View {
    @Environment(AppState.self) var appState
    @Environment(AgentSession.self) var session
    @Binding var stickToBottom: Bool
    /// When the composer has focus, confirmation cards must not steal Return.
    var composerFocused: Bool = false
    /// Mouse-down in the transcript — release composer focus so text selection can take first responder.
    var onBeginReading: () -> Void = {}

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
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in onBeginReading() }
                )
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

    var transcriptEventRevision: TranscriptEventRevision {
        let events = session.agent.state.events
        return TranscriptEventRevision(count: events.count, lastID: events.last?.id)
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
            Text("Drop files, paste a screenshot, or press ⇧⌘A to attach.")
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SageDesign.Spacing.large)
        .accessibilityElement(children: .combine)
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
    let retryState: RetryDisplayState?
    let canStop: Bool
    let onStop: () -> Void
    let onStreamScroll: () -> Void
    var status: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            if let status {
                HStack(spacing: SageDesign.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.system(size: SageDesign.Typography.bodySize))
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
                if streaming.isReservingWorkPlan {
                    MarkdownContentView(
                        markdown: streaming.text,
                        collapsible: true,
                        syntaxHighlighting: false
                    )
                    .transition(.opacity)
                } else {
                    StreamingContentView(text: streaming.text)
                        .transition(.opacity)
                }
            } else if status == nil, streaming.thinking.isEmpty, !streaming.isReservingWorkPlan {
                if let retry = retryState {
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
            if streaming.isReservingWorkPlan {
                WorkPlanCardSkeleton()
                    .transition(.opacity)
            }
        }
        .animation(SageDesign.Motion.streamingTransition, value: streaming.isActive)
        .animation(SageDesign.Motion.streamingTransition, value: streaming.isReservingWorkPlan)
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
