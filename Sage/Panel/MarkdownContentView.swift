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

    @State private var expanded = false
    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        Group {
            if collapsible, mayNeedCollapse {
                collapsibleBody
            } else {
                coreMarkdown
            }
        }
        .environment(\.openURL, PathTextSupport.openURLAction)
    }

    /// Skip expensive dual-layout measure for short replies.
    private var mayNeedCollapse: Bool {
        markdown.count >= SageDesign.Markdown.assistantMeasureCharacterGate
    }

    private var shouldOfferCollapse: Bool {
        measuredHeight > SageDesign.Markdown.collapsedReplyHeight + 8
    }

    private var coreMarkdown: some View {
        Markdown(markdown)
            .markdownTheme(.sage)
            .markdownCodeSyntaxHighlighter(TreeSitterCodeHighlighter())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsibleBody: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                // Unconstrained measurer — not visible, drives collapse decision.
                coreMarkdown
                    .fixedSize(horizontal: false, vertical: true)
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
            .onPreferenceChange(MarkdownHeightKey.self) { measuredHeight = $0 }

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
            if AccessibilityPreferences.reduceTransparency {
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

// MARK: - Disclosure control

struct MarkdownDisclosureButton: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(.primary.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Capsule())
        }
        .buttonStyle(SagePressableChipButtonStyle(emphasized: hovering))
        .onHover { hovering = $0 }
        .animation(SageDesign.Motion.contentCrossFade, value: expanded)
        .help(expanded ? "Collapse" : "Expand")
    }
}

// MARK: - Theme

extension Theme {
    /// Calm, system-native look for macOS agent transcripts.
    static let sage = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(13)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(.accentColor)
            UnderlineStyle(.single)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12)
            BackgroundColor(Color.primary.opacity(0.06))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(18)
                }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                }
                .markdownMargin(top: 10, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(13)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .codeBlock { configuration in
            SageCodeBlockView(configuration: configuration)
                .markdownMargin(top: 6, bottom: 10)
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                    }
                    .padding(.leading, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 6, bottom: 8)
        }
}

// MARK: - Code block chrome

private struct SageCodeBlockView: View {
    let configuration: CodeBlockConfiguration

    @State private var copied = false
    @State private var expanded = false

    private var lineCount: Int {
        configuration.content.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var needsCollapse: Bool {
        lineCount > SageDesign.Markdown.collapsedCodeLineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            codeScroll
            if needsCollapse {
                collapseBar
            }
        }
        .background(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if AccessibilityPreferences.increaseContrast {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(SageDesign.Chrome.strokeOpacity), lineWidth: 1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: SageDesign.Spacing.sm) {
            if let language = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines),
               !language.isEmpty {
                Text(language)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            copyButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private var copyButton: some View {
        Button {
            copyCode()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                Text(copied ? "Copied" : "Copy")
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
            }
            .foregroundStyle(.secondary)
            // ~10pt hit padding beyond the visual chip (Apple tap target guidance).
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(SagePressableChipButtonStyle())
        .help("Copy code")
        .accessibilityLabel(copied ? "Copied" : "Copy code")
    }

    private var codeScroll: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(SageDesign.Markdown.codeFontSize)
                }
                .padding(SageDesign.Markdown.codeBlockContentPadding)
                .frame(
                    maxHeight: needsCollapse && !expanded
                        ? SageDesign.Markdown.collapsedCodeContentHeight()
                        : nil,
                    alignment: .top
                )
                .clipped()
        }
    }

    private var collapseBar: some View {
        MarkdownDisclosureButton(
            title: expanded ? "Show less" : "Show more",
            expanded: expanded
        ) {
            withAnimation(SageDesign.Motion.expandAnimation) {
                expanded.toggle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configuration.content, forType: .string)

        withAnimation(SageDesign.Motion.copiedFeedback) {
            copied = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(SageDesign.Motion.contentCrossFade) {
                copied = false
            }
        }
    }
}

/// Instant press feedback — scale + fill on pointer-down (Apple response principle).
struct SagePressableChipButtonStyle: ButtonStyle {
    var emphasized: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color.primary.opacity(
                            configuration.isPressed ? 0.14 : (emphasized ? 0.10 : 0.06)
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(SageDesign.Motion.contentCrossFade, value: configuration.isPressed)
    }
}

private struct MarkdownHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
