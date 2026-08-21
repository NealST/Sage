//
//  SageCodeBlockView.swift
//  Sage
//

import AppKit
import MarkdownUI
import SwiftUI

/// Fenced code — github-markdown `pre` shape (muted well, 6pt radius, airy padding)
/// with Apple-native floating chrome instead of a heavy header / always-on scrollbar.
struct SageCodeBlockView: View {
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
                .padding(
                    .top,
                    SageDesign.Markdown.codeBlockContentPadding + SageDesign.Markdown.codeBlockChromeClearance
                )
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
