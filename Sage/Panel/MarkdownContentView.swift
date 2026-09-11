//
//  MarkdownContentView.swift
//  Sage
//

import AppKit
import MarkdownUI
import SwiftUI

/// Polished Markdown renderer for assistant replies (MarkdownUI).
struct MarkdownContentView: View {
    let markdown: String
    /// When true, long replies can collapse behind “Show more”.
    var collapsible: Bool = false
    /// TreeSitter highlighting — disable on the streaming hot path.
    var syntaxHighlighting: Bool = true
    /// Soft fade-in on first appear — for the streaming→commit hand-off where
    /// syntax colors would otherwise pop in abruptly.
    var appearsSoftly: Bool = false

    @State private var expanded: Bool
    @State private var measuredHeight: CGFloat = 0
    /// Hash of the markdown that produced `measuredHeight` — skip remounting the measurer.
    @State private var measuredMarkdownID: Int = 0
    @State private var revealOpacity: Double = 1
    @Environment(\.sageTypography) private var type

    /// - Parameter initiallyExpanded: long replies start expanded — used for
    ///   the just-committed reply so the text the user was reading while it
    ///   streamed doesn't snap shut on hand-off.
    init(
        markdown: String,
        collapsible: Bool = false,
        initiallyExpanded: Bool = false,
        syntaxHighlighting: Bool = true,
        appearsSoftly: Bool = false
    ) {
        self.markdown = markdown
        self.collapsible = collapsible
        self.syntaxHighlighting = syntaxHighlighting
        self.appearsSoftly = appearsSoftly
        _expanded = State(initialValue: initiallyExpanded)
        _revealOpacity = State(initialValue: appearsSoftly ? 0 : 1)
    }

    /// Presentation-only markdown (completed tasks softened). Source `markdown` is unchanged.
    private var displayMarkdown: String {
        MarkdownPresentation.softenCompletedTasks(in: markdown)
    }

    var body: some View {
        Group {
            if collapsible, mayNeedCollapse {
                collapsibleBody
            } else {
                coreMarkdown
            }
        }
        .opacity(revealOpacity)
        .onAppear {
            guard appearsSoftly, revealOpacity == 0 else { return }
            withAnimation(SageDesign.Motion.streamingTransition) {
                revealOpacity = 1
            }
        }
        .environment(\.openURL, PathTextSupport.openURLAction)
        .onChange(of: markdown) { _, _ in
            // Content changed: re-measure, but keep the user's expand choice.
            measuredMarkdownID = 0
            measuredHeight = 0
        }
    }

    /// Skip expensive dual-layout measure for short replies.
    private var mayNeedCollapse: Bool {
        displayMarkdown.count >= SageDesign.Markdown.assistantMeasureCharacterGate
    }

    /// Rough height estimate while the first real measurement is pending,
    /// so the placeholder doesn't jump from zero.
    private var measuredPlaceholderHeight: CGFloat {
        let lineEstimate = CGFloat(displayMarkdown.count) / 60
        return lineEstimate * (type.reading * 1.5)
    }

    private var shouldOfferCollapse: Bool {
        measuredHeight > SageDesign.Markdown.collapsedReplyHeight + 8
    }

    private var needsFreshMeasure: Bool {
        measuredMarkdownID != displayMarkdown.hashValue || measuredHeight <= 0
    }

    /// Visible tree — TreeSitter only when `syntaxHighlighting` is on.
    private var coreMarkdown: some View {
        Group {
            if syntaxHighlighting {
                Markdown(displayMarkdown)
                    .markdownTheme(.sage(readingSize: type.reading))
                    .markdownCodeSyntaxHighlighter(TreeSitterCodeHighlighter())
            } else {
                Markdown(displayMarkdown)
                    .markdownTheme(.sage(readingSize: type.reading))
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Offscreen measurer — same theme, no TreeSitter (highlighting isn't needed for height).
    private var measureMarkdown: some View {
        Markdown(displayMarkdown)
            .markdownTheme(.sage(readingSize: type.reading))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var collapsibleBody: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            ZStack(alignment: .topLeading) {
                if needsFreshMeasure {
                    measureMarkdown
                        .hidden()
                        .accessibilityHidden(true)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: MarkdownHeightKey.self,
                                    value: geo.size.height
                                )
                            }
                        }
                }

                // Collapsed state waits for the first measurement — rendering
                // before it shows a full-height frame that then snaps to the
                // collapsed height (a visible flash on commit and re-materialize).
                if expanded || !needsFreshMeasure {
                    coreMarkdown
                        .frame(
                            maxHeight: (!expanded && shouldOfferCollapse)
                                ? SageDesign.Markdown.collapsedReplyHeight
                                : nil,
                            alignment: .top
                        )
                        .clipped()
                        .overlay(alignment: .bottom) {
                            if !expanded, shouldOfferCollapse {
                                collapseFade
                            }
                        }
                } else {
                    Color.clear
                        .frame(height: min(
                            measuredPlaceholderHeight,
                            SageDesign.Markdown.collapsedReplyHeight
                        ))
                }
            }
            .onPreferenceChange(MarkdownHeightKey.self) { height in
                measuredHeight = height
                measuredMarkdownID = displayMarkdown.hashValue
            }

            if shouldOfferCollapse {
                MarkdownDisclosureButton(
                    title: expanded ? "Show less" : "Show more",
                    expanded: expanded
                ) {
                    withAnimation(SageDesign.Motion.expandAnimation) {
                        expanded.toggle()
                    }
                }
            }
        }
    }

    /// Fade into the reading canvas — same window fill, not a second material.
    private var collapseFade: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor).opacity(0),
                Color(nsColor: .windowBackgroundColor),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 52)
        .allowsHitTesting(false)
    }
}

private struct MarkdownHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
