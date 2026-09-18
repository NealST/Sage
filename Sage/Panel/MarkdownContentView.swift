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
    /// Fired after the user toggles Show more / Show less so a transcript can
    /// keep this reply in view when the height collapses.
    var onExpansionChange: ((Bool) -> Void)? = nil

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
        appearsSoftly: Bool = false,
        onExpansionChange: ((Bool) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.collapsible = collapsible
        self.syntaxHighlighting = syntaxHighlighting
        self.appearsSoftly = appearsSoftly
        self.onExpansionChange = onExpansionChange
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
            coreMarkdown
                .frame(
                    maxHeight: clipsToCollapsedHeight
                        ? SageDesign.Markdown.collapsedReplyHeight
                        : nil,
                    alignment: .top
                )
                .clipped()
                .mask(alignment: .top) {
                    if clipsToCollapsedHeight {
                        // Content fades out toward the fold instead of
                        // being covered by a painted canvas color — the
                        // reveal matches any surface, including the
                        // translucent window material.
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: SageDesign.Markdown.foldFadeHeight)
                        }
                    } else {
                        Color.black
                    }
                }
                .background(alignment: .top) {
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
                }
            .onPreferenceChange(MarkdownHeightKey.self) { height in
                // Removing the measurer republishes the key's default (0).
                // Keep the last real height or Show less draws an empty hole.
                guard height > 0 else { return }
                measuredHeight = height
                measuredMarkdownID = displayMarkdown.hashValue
            }

            if shouldOfferCollapse {
                MarkdownDisclosureButton(
                    title: expanded ? "Show less" : "Show more",
                    expanded: expanded
                ) {
                    let next = !expanded
                    withAnimation(SageDesign.Motion.expandAnimation) {
                        expanded = next
                        onExpansionChange?(next)
                    }
                }
            }
        }
    }

    /// Clip while collapsed, including the first measure pass so a long
    /// reply never flashes at full height (or as an empty placeholder).
    private var clipsToCollapsedHeight: Bool {
        !expanded && (shouldOfferCollapse || needsFreshMeasure)
    }

}

private struct MarkdownHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
