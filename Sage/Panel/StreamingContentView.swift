//
//  StreamingContentView.swift
//  Sage
//

import MarkdownUI
import SwiftUI

/// Displays incrementally streamed text with a breathing cursor at the end.
///
/// Uses a two-layer optimization for performance:
/// 1. **Block splitting** — completed markdown blocks are cached and never re-parsed.
/// 2. **Throttling** — the active (last) block is re-rendered at most every ~100ms.
///
/// The cursor pulses with an organic easeInOut rhythm (not a hard blink)
/// and respects `reduceMotion` — showing a static caret when motion is reduced.
struct StreamingContentView: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sageTypography) private var type
    @State private var cursorOpacity: Double = 1.0
    @State private var throttledState = ThrottledStreamState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !text.isEmpty {
                streamingBlocks
            }
            streamingCursor
                .padding(.top, text.isEmpty ? 0 : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { _, newValue in
            throttledState.update(with: newValue)
        }
        .onAppear {
            throttledState.update(with: text)
        }
        .onDisappear {
            // Flush any pending throttled content before the view is removed,
            // ensuring no tokens are lost during the streaming→committed transition.
            throttledState.flushNow()
        }
    }

    private var streamingBlocks: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Completed blocks — stable, SwiftUI skips body when markdown is unchanged.
            if !throttledState.committedMarkdown.isEmpty {
                CachedMarkdownBlock(markdown: throttledState.committedMarkdown)
                    .equatable()
            }
            // Active (last) block — throttled re-renders; no TreeSitter on the hot path.
            if !throttledState.activeBlockMarkdown.isEmpty {
                MarkdownContentView(
                    markdown: throttledState.activeBlockMarkdown,
                    syntaxHighlighting: false
                )
            }
        }
    }

    private var streamingCursor: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.secondary)
            .frame(width: 2, height: type.body + 2)
            .opacity(cursorOpacity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(SageDesign.Motion.cursorPulse) {
                    cursorOpacity = 0.2
                }
            }
            .accessibilityLabel("Generating response")
    }
}

// MARK: - Throttled Stream State

/// Manages block splitting and render throttling for streaming markdown.
///
/// Splits the incoming text at block boundaries (double newlines, fenced code block
/// delimiters) and only updates the active block on a throttle interval.
@MainActor
@Observable
private final class ThrottledStreamState {
    /// All completed blocks joined — stable content that won't change.
    private(set) var committedMarkdown: String = ""
    /// The last (in-progress) block — updated at throttled intervals.
    private(set) var activeBlockMarkdown: String = ""

    private var pendingActiveBlock: String = ""
    private var throttleTask: Task<Void, Never>?
    private var lastRenderTime: ContinuousClock.Instant = .now

    private static let throttleInterval: Duration = .milliseconds(100)

    /// Immediately flush any pending active block content (called on view disappear).
    func flushNow() {
        throttleTask?.cancel()
        throttleTask = nil
        flushActiveBlock()
    }

    func update(with fullText: String) {
        let (committed, active) = splitBlocks(fullText)

        // Committed blocks changed — update immediately (this is rare, ~once per block completion)
        if committed != committedMarkdown {
            committedMarkdown = committed
        }

        pendingActiveBlock = active
        scheduleActiveBlockUpdate()
    }

    private func scheduleActiveBlockUpdate() {
        // If enough time has passed, update immediately
        let elapsed = ContinuousClock.now - lastRenderTime
        if elapsed >= Self.throttleInterval {
            flushActiveBlock()
            return
        }

        // Otherwise schedule a deferred update (coalesce rapid token arrivals)
        guard throttleTask == nil else { return }
        let remaining = Self.throttleInterval - elapsed
        throttleTask = Task { [weak self] in
            try? await Task.sleep(for: remaining)
            guard let self, !Task.isCancelled else { return }
            self.flushActiveBlock()
            self.throttleTask = nil
        }
    }

    private func flushActiveBlock() {
        activeBlockMarkdown = pendingActiveBlock
        lastRenderTime = .now
    }

    /// Splits markdown text into (committed blocks, active block).
    ///
    /// A block is "committed" once a subsequent block boundary is detected,
    /// meaning the block's semantics can no longer change.
    /// The split point is chosen at the start of a blank line sequence (`\n\n`)
    /// that is NOT inside a fenced code block.
    private func splitBlocks(_ text: String) -> (committed: String, active: String) {
        guard !text.isEmpty else { return ("", "") }

        // Scan for the last block boundary: a `\n\n` sequence outside fenced code.
        // We track whether we're inside a fenced code block by counting fence openers/closers.
        var inFencedCode = false
        var lastBoundary: String.Index?
        var i = text.startIndex
        var lineStart = text.startIndex

        while i < text.endIndex {
            // At the start of each line, check for fence markers
            if i == lineStart {
                let lineEnd = text[i...].firstIndex(of: "\n") ?? text.endIndex
                let line = text[i..<lineEnd]
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    inFencedCode.toggle()
                }
            }

            // Detect \n\n (blank line boundary) outside fenced code
            if !inFencedCode,
               text[i] == "\n",
               text.index(after: i) < text.endIndex,
               text[text.index(after: i)] == "\n" {
                // The boundary is at the second \n — the active block starts after it.
                // But we want committed to include up to (and including) the first \n,
                // and active to start from the second \n onward.
                let boundaryStart = text.index(after: i) // points to second \n
                // Only record if there's content after the boundary
                let afterBoundary = text.index(after: boundaryStart)
                if afterBoundary <= text.endIndex {
                    lastBoundary = afterBoundary
                }
            }

            // Advance to next character, tracking line starts
            let next = text.index(after: i)
            if text[i] == "\n" && next < text.endIndex {
                lineStart = next
            }
            i = next
        }

        guard let boundary = lastBoundary, boundary < text.endIndex else {
            return ("", text)
        }

        let committed = String(text[text.startIndex..<boundary])
        let active = String(text[boundary...])
        return (committed, active)
    }
}

// MARK: - Cached Markdown Block

/// A markdown view that conforms to Equatable so SwiftUI can skip body re-evaluation
/// when the markdown string hasn't changed. Used for committed (stable) blocks.
private struct CachedMarkdownBlock: View, Equatable {
    let markdown: String

    var body: some View {
        MarkdownContentView(markdown: markdown)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.markdown == rhs.markdown
    }
}
