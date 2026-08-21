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

    @Environment(\.pathGuardPolicy) private var pathGuardPolicy
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

    private var expandTransition: AnyTransition {
        if AccessibilityPreferences.reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                bodyContent
                    .transition(expandTransition)
            }
        }
        // Stable continuous corner — avoid morphing capsule↔rect while expanding.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
        )
        .overlay {
            if AccessibilityPreferences.increaseContrast {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(SageDesign.Chrome.strokeOpacity), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .font(.system(size: SageDesign.Typography.iconSize, weight: .semibold))
                Text(title)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolResultHeaderButtonStyle())
        .foregroundStyle(isError ? Color.orange : Color.secondary)
        .accessibilityLabel(expanded ? "Collapse tool result" : "Expand tool result")
        .accessibilityValue(title)
        .help(expanded ? "Hide details" : "Show full tool result")
        .animation(SageDesign.Motion.expandAnimation, value: expanded)
    }

    private var headerIcon: String {
        split.payload != nil ? "square.and.pencil" : SageDesign.Symbol.tools
    }

    @ViewBuilder
    private var bodyContent: some View {
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
            } else {
                Text(PathTextSupport.attributedString(from: split.summary, policy: pathGuardPolicy))
                    .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .contextMenu { pathContextMenu }
            }
        }
    }

    @ViewBuilder
    private var pathContextMenu: some View {
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

private struct ToolResultHeaderButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : SageDesign.Motion.contentCrossFade,
                value: configuration.isPressed
            )
    }
}
