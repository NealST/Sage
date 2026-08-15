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
    /// GitHub-flavored structure with Apple system colors and airy reading rhythm.
    ///
    /// Layout mirrors `Theme.gitHub` / github-markdown-css (heading rules, tables,
    /// blockquotes, task lists) but uses semantic AppKit colors so light/dark and
    /// accessibility contrast follow the system — no Primer hex tokens.
    /// Deliberately omits a page `BackgroundColor` so the panel material shows through.
    static let sage = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .strong {
            FontWeight(.semibold)
        }
        .strikethrough {
            StrikethroughStyle(.single)
            ForegroundColor(.secondary)
        }
        .link {
            ForegroundColor(.accentColor)
            UnderlineStyle(.single)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            BackgroundColor(Color(nsColor: .quaternarySystemFill))
        }
        // Modest top margins so a leading heading isn’t airy-empty (CSS first-child
        // collapse). Breathing between blocks comes mostly from previous bottom margins.
        .heading1 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.35))
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 8, bottom: 16)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.65))
                    }
                Divider().overlay(Color(nsColor: .separatorColor))
            }
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 10, bottom: 14)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.35))
                    }
                Divider().overlay(Color(nsColor: .separatorColor))
            }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 10, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.15))
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 8, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.0))
                }
        }
        .heading5 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 8, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.92))
                    ForegroundColor(.secondary)
                }
        }
        .heading6 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 8, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.88))
                    ForegroundColor(.secondary)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.38))
                .markdownMargin(top: 0, bottom: 16)
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 8, bottom: 16)
        }
        .codeBlock { configuration in
            SageCodeBlockView(configuration: configuration)
                .markdownMargin(top: 8, bottom: 16)
        }
        .image { configuration in
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .markdownMargin(top: 10, bottom: 16)
        }
        .list { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 16)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.28), bottom: .em(0.12))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    configuration.isCompleted ? Color.secondary.opacity(0.7) : Color.secondary,
                    Color(nsColor: .quaternarySystemFill)
                )
                .imageScale(.small)
                .relativeFrame(minWidth: .em(1.6), alignment: .trailing)
        }
        .table { configuration in
            ScrollView(.horizontal, showsIndicators: true) {
                configuration.label
                    .fixedSize(horizontal: true, vertical: true)
                    .markdownTableBorderStyle(.init(color: Color(nsColor: .separatorColor)))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(
                            Color.clear,
                            Color(nsColor: .quaternarySystemFill)
                        )
                    )
            }
            .markdownMargin(top: 4, bottom: 16)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .relativeLineSpacing(.em(0.3))
        }
        .thematicBreak {
            Divider()
                .overlay(Color(nsColor: .separatorColor))
                .padding(.vertical, 8)
                .markdownMargin(top: 20, bottom: 20)
        }
}

// MARK: - Code block chrome

/// Fenced code — github-markdown `pre` shape (muted well, 6pt radius, airy padding)
/// with Apple-native floating chrome instead of a heavy header / always-on scrollbar.
private struct SageCodeBlockView: View {
    let configuration: CodeBlockConfiguration

    @Environment(AccessibilitySettings.self) private var accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var expanded = false
    @State private var hovering = false

    private var lineCount: Int {
        configuration.content.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var needsCollapse: Bool {
        lineCount > SageDesign.Markdown.collapsedCodeLineLimit
    }

    private var languageLabel: String? {
        let raw = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private var cornerRadius: CGFloat { SageDesign.Markdown.codeBlockCornerRadius }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                codeScroll
                floatingChrome
            }
            if needsCollapse {
                collapseControl
            }
        }
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color(nsColor: .separatorColor).opacity(accessibility.increaseContrast ? 0.9 : 0.28),
                    lineWidth: 1
                )
        }
        .onHover { hovering = $0 }
    }

    private var codeScroll: some View {
        ScrollView(.horizontal) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.25))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(SageDesign.Markdown.codeFontSize)
                }
                .padding(.top, SageDesign.Markdown.codeBlockContentPadding + SageDesign.Markdown.codeBlockChromeClearance)
                .padding(.horizontal, SageDesign.Markdown.codeBlockContentPadding)
                .padding(.bottom, SageDesign.Markdown.codeBlockContentPadding)
                .frame(
                    maxHeight: needsCollapse && !expanded
                        ? SageDesign.Markdown.collapsedCodeContentHeight()
                        : nil,
                    alignment: .top
                )
                .clipped()
        }
        // Trackpad / Magic Mouse still scroll; hide the fat always-visible bar.
        .scrollIndicators(.hidden)
    }

    /// Language caption + icon-only copy — GitHub-style hover affordance, SF chrome.
    private var floatingChrome: some View {
        HStack(alignment: .center, spacing: 8) {
            if let languageLabel {
                Text(languageLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            copyButton
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .opacity(chromeOpacity)
        .animation(SageDesign.Motion.contentCrossFade, value: hovering)
        .animation(SageDesign.Motion.contentCrossFade, value: copied)
    }

    private var chromeOpacity: Double {
        if copied || accessibility.increaseContrast { return 1 }
        return hovering ? 1 : 0.55
    }

    private var copyButton: some View {
        Button {
            copyCode()
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(copied ? Color.secondary : Color.secondary.opacity(0.9))
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                        }
                }
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy code")
        .accessibilityLabel(copied ? "Copied" : "Copy code")
    }

    /// Quiet text control — no filled footer strip.
    private var collapseControl: some View {
        Button {
            withAnimation(SageDesign.Motion.expandAnimation) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(expanded ? "Show less" : "Show more")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Divider().opacity(SageDesign.Chrome.dividerOpacity)
        }
        .help(expanded ? "Collapse" : "Expand")
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configuration.content, forType: .string)

        withAnimation(reduceMotion ? nil : SageDesign.Motion.copiedFeedback) {
            copied = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(SageDesign.Motion.contentCrossFade) {
                copied = false
            }
        }
    }
}

/// Instant press feedback — opacity always; scale only when Reduce Motion is off.
struct SagePressableChipButtonStyle: ButtonStyle {
    var emphasized: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : SageDesign.Motion.contentCrossFade,
                value: configuration.isPressed
            )
    }
}

private struct MarkdownHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
