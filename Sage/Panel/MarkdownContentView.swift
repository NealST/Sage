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

    @Environment(AccessibilitySettings.self) private var accessibility
    @State private var expanded = false
    @State private var measuredHeight: CGFloat = 0
    /// Hash of the markdown that produced `measuredHeight` — skip remounting the measurer.
    @State private var measuredMarkdownID: Int = 0

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
        .environment(\.openURL, PathTextSupport.openURLAction)
        .onChange(of: markdown) { _, _ in
            expanded = false
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
                    .markdownTheme(.sage)
                    .markdownCodeSyntaxHighlighter(TreeSitterCodeHighlighter())
            } else {
                Markdown(displayMarkdown)
                    .markdownTheme(.sage)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Offscreen measurer — same theme, no TreeSitter (highlighting isn't needed for height).
    private var measureMarkdown: some View {
        Markdown(displayMarkdown)
            .markdownTheme(.sage)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var collapsibleBody: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
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

    /// Scroll-edge style fade that matches the canvas (material) instead of a hard window fill.
    private var collapseFade: some View {
        Group {
            if accessibility.reduceTransparency {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0),
                        Color(nsColor: .windowBackgroundColor),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Rectangle()
                    .fill(.regularMaterial)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
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
