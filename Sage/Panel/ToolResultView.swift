//
//  ToolResultView.swift
//  Sage
//

import AppKit
import SwiftUI

/// Expandable tool-result chip. Paths in the body are tappable (Finder / Quick Look).
/// Write-file results expand to a unified before/after diff when a payload is present.
struct ToolResultView: View {
    let content: String

    /// Cap for the expanded plain-text body before it becomes scrollable.
    static let expandedBodyMaxHeight: CGFloat = 320

    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
    @Environment(\.sageTypography) private var type
    @State private var expanded: Bool

    init(content: String) {
        self.content = content
        _expanded = State(initialValue: Self.shouldStartExpanded(content))
    }

    private var isError: Bool {
        content.hasPrefix("ERROR:")
    }

    private var split: (summary: String, payload: WriteFileDiffPayload?) {
        WriteFileResultCodec.split(content)
    }

    private var title: String {
        if isError {
            let detail = content.dropFirst("ERROR:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty { return "Tool failed" }
            return detail.count <= 72 ? "Failed: \(detail)" : "Failed: \(detail.prefix(66))…"
        }

        var line = split.summary.split(separator: "\n", maxSplits: 1).first.map(String.init)
            ?? split.summary
        if line.hasPrefix("[OK] ") {
            line = String(line.dropFirst(5))
        } else if line.hasPrefix("[OK]") {
            line = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        // Legacy absolute write payloads → show project-relative in the chip title.
        if let payload = split.payload {
            let relative = PathGuard.displayPath(payload.path, policy: pathGuardPolicy)
            if relative != payload.path {
                line = line.replacingOccurrences(of: payload.path, with: relative)
            }
        }
        if line.count <= 72 { return line }
        return String(line.prefix(69)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                bodyContent
                    .transition(ToolChipChrome.expandTransition)
            }
        }
        // Stable continuous corner — avoid morphing capsule↔rect while expanding.
        .sageToolChipSurface()
        .environment(\.openURL, PathTextSupport.openURLAction)
    }

    private var header: some View {
        Button {
            withAnimation(SageDesign.Motion.expandAnimation) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isError ? SageDesign.Symbol.stepFailed : headerIcon)
                    .sageFont(type.icon, weight: .semibold)
                    .foregroundStyle(headerIconColor)
                    // Pinned column so the title starts at the same x across
                    // chips regardless of glyph width.
                    .frame(width: 14, alignment: .center)
                Text(title)
                    .sageMicro(type.micro, weight: .medium)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .sageFont(type.icon, weight: .semibold)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolChipHeaderButtonStyle())
        .foregroundStyle(isError ? SageDesign.Palette.danger : Color.secondary)
        .accessibilityLabel(expanded ? "Collapse tool result" : "Expand tool result")
        .accessibilityValue(title)
        .help(expanded ? "Hide details" : "Show full tool result")
        .animation(SageDesign.Motion.expandAnimation, value: expanded)
    }

    private var headerIcon: String {
        if split.payload != nil { return "square.and.pencil" }
        return SageDesign.Symbol.stepSuccess
    }

    /// Same status vocabulary as transcript step icons: green check for plain
    /// successes, red cross for failures, neutral for diff previews.
    private var headerIconColor: Color {
        if isError { return SageDesign.Palette.danger }
        if split.payload != nil { return .secondary }
        return SageDesign.Palette.success
    }

    @ViewBuilder private var bodyContent: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            if let payload = split.payload {
                UnifiedDiffView(
                    before: payload.before,
                    after: payload.after,
                    created: payload.created,
                    truncated: payload.truncated,
                    path: PathGuard.displayPath(payload.path, policy: pathGuardPolicy),
                    statsOverride: payload.stats
                )
                .padding(.bottom, 10)
                .contextMenu { payloadContextMenu(payload) }
            } else {
                ScrollView {
                    Text(PathTextSupport.attributedString(from: split.summary, policy: pathGuardPolicy))
                        .sageFont(type.caption, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Huge outputs (file dumps, long listings) scroll instead of
                // stretching the transcript.
                .frame(maxHeight: Self.expandedBodyMaxHeight)
                // Fade at the fold — same composite as the chip surface, so it
                // reads as "more below" and vanishes on short content.
                .overlay(alignment: .bottom) {
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        Color.primary.opacity(SageDesign.Chrome.pillFillOpacity)
                    }
                    .frame(height: 36)
                    .mask {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .contextMenu { pathContextMenu }
            }
        }
    }

    /// Copy / Reveal affordances for write-diff results — the plain-text
    /// branch has the same reachability.
    @ViewBuilder private func payloadContextMenu(_ payload: WriteFileDiffPayload) -> some View {
        let url = URL(fileURLWithPath: payload.path)
        Button("Reveal “\(url.lastPathComponent)” in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        Divider()
        Button("Copy New File Contents") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(payload.after, forType: .string)
        }
        Button("Copy Result") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
        }
    }

    @ViewBuilder private var pathContextMenu: some View {
        let display = split.summary
        let urls = PathTextSupport.allFileURLs(in: display, policy: pathGuardPolicy)
        if urls.isEmpty {
            Button("Copy Result") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(display, forType: .string)
            }
        } else {
            ForEach(urls, id: \.path) { url in
                if PathTextSupport.isImagePath(url.path) {
                    Button("Quick Look “\(url.lastPathComponent)”") {
                        QuickLookPresenter.shared.preview(url: url)
                    }
                }
                Button("Reveal “\(url.lastPathComponent)” in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Divider()
            Button("Copy Result") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(display, forType: .string)
            }
        }
    }

    private static func shouldStartExpanded(_ content: String) -> Bool {
        if content.hasPrefix("ERROR:") { return true }
        if WriteFileResultCodec.payload(in: content) != nil { return true }
        let summary = WriteFileResultCodec.modelFacing(content)
        let lines = summary.split(separator: "\n", omittingEmptySubsequences: false)
        return summary.count <= SageDesign.Markdown.shortToolResultCharacterLimit
            && lines.count <= SageDesign.Markdown.shortToolResultLineLimit
    }
}
