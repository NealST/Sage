//
//  DesignTokens.swift
//  Sage
//

import AppKit
import SwiftUI

enum SageDesign {
    enum Spacing {
        static let extraSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 24
        /// Inner padding for transcript chip headers (tool results, status
        /// pills) — one value so same-density chips never drift apart.
        static let chipHorizontal: CGFloat = 12
        static let chipVertical: CGFloat = 8
        /// Icon↔text gap inside chips and labels — optical, not grid-aligned.
        static let labelGap: CGFloat = 6
        /// Compact chrome chips (titlebar, notice-bar text actions) — denser
        /// than transcript chips because their host bands are single-purpose.
        static let compactChipHorizontal: CGFloat = 8
        static let compactChipVertical: CGFloat = 4
        /// Title-over-detail stack inside one label — deliberately tighter than
        /// any layout gap so the pair reads as a single unit.
        static let titleDetailGap: CGFloat = 2
    }

    /// Persistent agent workspace window.
    enum Panel {
        static let width: CGFloat = 760
        static let height: CGFloat = 580
        /// Single unified titlebar row (aligns with traffic lights).
        static let titlebarContentHeight: CGFloat = 52
        /// Traffic-light clearance for the titlebar chrome row: the lights
        /// end at window x ≈ 80 on the unified toolbar band, so identity
        /// content starts past them. Page content (transcript, composer)
        /// keeps `Spacing.large` instead — those two share one left edge.
        static let titlebarLeadingInset: CGFloat = 88
        /// Reading measure for transcript content — wide or fullscreen
        /// windows must not stretch reply lines past comfortable length.
        static let readingColumnWidth: CGFloat = 720
        /// Resize floor for the agent window (initial size is width/height).
        static let minWidth: CGFloat = 560
        static let minHeight: CGFloat = 440
    }

    enum Typography {
        static let inputSize: CGFloat = 15
        static let bodySize: CGFloat = 13
        /// Assistant-reply reading canvas — slightly larger than chrome body
        /// (github-markdown ratio). MarkdownUI theme scales from this.
        static let readingSize: CGFloat = 14
        static let captionSize: CGFloat = 12
        static let titleSize: CGFloat = 15
        static let microSize: CGFloat = 11
        static let iconSize: CGFloat = 10
    }

    /// Contrast-aware surface opacities for fills, strokes, and dividers.
    /// Prefer `@Environment(AccessibilitySettings.self)` in views so values refresh live.
    enum Chrome {
        @MainActor
        static var fillOpacity: Double { AccessibilitySettings.shared.fillOpacity }
        @MainActor
        static var strongFillOpacity: Double { AccessibilitySettings.shared.strongFillOpacity }
        @MainActor
        static var pillFillOpacity: Double { AccessibilitySettings.shared.pillFillOpacity }
        @MainActor
        static var selectionFillOpacity: Double { AccessibilitySettings.shared.selectionFillOpacity }
        @MainActor
        static var accentRingOpacity: Double { AccessibilitySettings.shared.accentRingOpacity }
        @MainActor
        static var diffFillOpacity: Double { AccessibilitySettings.shared.diffFillOpacity }
        @MainActor
        static var strokeOpacity: Double { AccessibilitySettings.shared.strokeOpacity }
        @MainActor
        static var dividerOpacity: Double { AccessibilitySettings.shared.dividerOpacity }
        /// Non-matching content while in-task find is active — stronger
        /// de-emphasis under Increase Contrast so matches stand out further.
        @MainActor
        static var dimmedContentOpacity: Double {
            AccessibilitySettings.shared.increaseContrast ? 0.15 : 0.3
        }
        /// Disabled custom-styled controls — styles that draw their own
        /// chrome must dim themselves; the system treatment only covers
        /// native control appearances.
        @MainActor
        static var disabledControlOpacity: Double {
            AccessibilitySettings.shared.increaseContrast ? 0.3 : 0.45
        }
        /// De-emphasized but still-readable content (diff context lines,
        /// completed checklist markers, queued status) — between secondary
        /// and tertiary, stronger under Increase Contrast.
        @MainActor
        static var deemphasizedContentOpacity: Double {
            AccessibilitySettings.shared.increaseContrast ? 0.55 : 0.7
        }
    }

    /// Interactive-control metrics — icon frames, hit targets, status dots.
    enum Control {
        /// Pinned symbol column so chip titles start at the same x regardless
        /// of glyph width.
        static let iconColumnWidth: CGFloat = 14
        /// Inline icon buttons in compact bars (find-bar steppers).
        static let iconButtonCompact: CGFloat = 20
        /// Standalone quiet icon buttons (attach, copy chips).
        static let iconButton: CGFloat = 22
        /// Prominent / overflow icon buttons (submit, retry ring, ellipsis).
        static let iconButtonLarge: CGFloat = 24
        /// macOS comfortable hit floor — small visual frames grow their
        /// tappable area to reach this (`sageHitSlop`).
        static let minimumHitTarget: CGFloat = 28
        /// Status dot diameter (schedule rows, connection state).
        static let statusDotDiameter: CGFloat = 8
    }

    /// Semantic colors — one meaning each so error treatments never drift.
    /// Warnings and transient attention states (awaiting confirmation, retrying,
    /// connecting, budget low) stay orange; `danger` is for failures only.
    /// `success` covers completions and diff insertions (green = added).
    ///
    /// Two tiers: the plain colors are for icons, status dots, and fills;
    /// the `*Text` variants are for any view whose meaning is carried by
    /// text drawn directly on a content surface.
    nonisolated enum Palette {
        static let danger = Color(nsColor: .systemRed)
        static let warning = Color(nsColor: .systemOrange)
        static let success = Color(nsColor: .systemGreen)

        /// Text-bearing variants: small text needs 4.5:1 (HIG) and the
        /// light-mode system orange/green sit near 2.2:1 on the light window
        /// material (red ~3.4:1). Light uses fixed dark shades that hold
        /// 4.5:1+ even over the 14% diff-row tints; dark keeps the system
        /// colors, which are contrast-engineered for dark surfaces and
        /// strengthen under Increase Contrast.
        static let dangerText = textSafe(red: 0xB6, green: 0x24, blue: 0x2B, dark: .danger)
        static let warningText = textSafe(red: 0xA6, green: 0x3D, blue: 0x00, dark: .warning)
        static let successText = textSafe(red: 0x11, green: 0x63, blue: 0x29, dark: .success)

        /// Quiet surface fill for markdown content (checklist cells, code
        /// chrome) — the system fill that sits below `controlBackgroundColor`.
        static let subtleFill = Color(nsColor: .quaternarySystemFill)
        /// Hairline divider for markdown content blocks and code chrome.
        static let hairline = Color(nsColor: .separatorColor)

        /// Which system color the dark half of a text-safe pair resolves to.
        private enum TextSafeDark: Sendable {
            case danger, warning, success

            var systemColor: NSColor {
                switch self {
                case .danger: return .systemRed
                case .warning: return .systemOrange
                case .success: return .systemGreen
                }
            }
        }

        /// The provider closure may be retained by AppKit and invoked on any
        /// appearance change, so it only captures Sendable values (the enum
        /// and the raw components) and builds NSColors inside.
        private static func textSafe(
            red: UInt8,
            green: UInt8,
            blue: UInt8,
            dark: TextSafeDark
        ) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                if isDarkAppearance(appearance) {
                    return dark.systemColor
                }
                return NSColor(
                    srgbRed: CGFloat(red) / 255,
                    green: CGFloat(green) / 255,
                    blue: CGFloat(blue) / 255,
                    alpha: 1
                )
            })
        }

        private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
            switch appearance.name {
            case .darkAqua, .accessibilityHighContrastDarkAqua:
                return true
            case .aqua, .accessibilityHighContrastAqua:
                return false
            default:
                return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
    }

    enum Motion {
        static let contentCrossFade: Animation = .easeOut(duration: 0.18)
        static let reducedCrossFade: Animation = .easeOut(duration: 0.12)

        /// Window-level alpha fades (AppKit, seconds). Short on purpose —
        /// showing a window must stay effectively instant.
        static let windowFadeInDuration: TimeInterval = 0.18
        static let windowFadeOutDuration: TimeInterval = 0.15

        /// Chrome icon help labels. The system tooltip waits ~1s and draws a
        /// square window; this is short enough to feel like a hover label.
        static let helpShowDelay: TimeInterval = 0.2
        /// Keep the current label up while the pointer crosses adjacent icons.
        static let helpHideGrace: TimeInterval = 0.08
        /// Gap between the control and the help label under it.
        static let helpGap: CGFloat = 6

        /// Critically damped spring for streaming scroll — no overshoot, smooth
        /// settle. `nil` under Reduce Motion so callers animate without checks.
        static var streamingScroll: Animation? {
            AccessibilityPreferences.reduceMotion
                ? nil
                : .interpolatingSpring(duration: 0.3, bounce: 0)
        }

        /// Expand/collapse (tool results, Show more) — critically damped, no bounce.
        static let expandCollapse: Animation = .interpolatingSpring(duration: 0.32, bounce: 0)

        /// Drag-cancel settle (attachment chip spring-back, tips banner).
        /// Critically damped so the return never overshoots; `nil` under
        /// Reduce Motion so callers animate without checks.
        static var dragSettle: Animation? {
            AccessibilityPreferences.reduceMotion
                ? nil
                : .interpolatingSpring(duration: 0.3, bounce: 0)
        }

        /// Drag-release settle seeded with the gesture's velocity — the
        /// element keeps moving at the finger's speed through the spring-back
        /// instead of stopping dead and then easing home. `velocity` is px/s
        /// on the animated axis; the API wants it normalized by remaining
        /// displacement per duration (clamped: a release just past the
        /// threshold would otherwise produce an extreme kick). Works for both
        /// spring-back (target 0) and throw-out commits (target past the
        /// threshold) so the commit path carries the gesture's momentum too.
        static func dragSettle(
            velocity: CGFloat,
            from current: CGFloat,
            to target: CGFloat = 0
        ) -> Animation? {
            guard !AccessibilityPreferences.reduceMotion else { return nil }
            let displacement = target - current
            guard abs(displacement) > 0.5 else { return dragSettle }
            let normalized = (Double(velocity) * 0.3) / Double(displacement)
            let clamped = min(max(normalized, -2), 2)
            return .interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: clamped)
        }

        /// Brief settle after copy confirmation.
        static let copiedFeedback: Animation = .interpolatingSpring(duration: 0.28, bounce: 0)

        /// Confirmation flashes (copied / saved chips) — one duration so
        /// sibling feedback reads as the same idiom.
        static let feedbackFlashDuration: TimeInterval = 1.4

        /// Drag throw-out commits, shared by the attachment chip (up =
        /// remove) and the tips banner (down = dismiss): the flick velocity
        /// that commits past the distance threshold, how far past the release
        /// point the throw carries, and the beat the element spends invisible
        /// before the removal actually lands.
        enum DragThrow {
            static let flickVelocity: CGFloat = 600
            static let distance: CGFloat = 110
            static let removalDelay: TimeInterval = 0.22
        }

        /// Press feedback (chip / header micro-scale) — a press is a physical
        /// interaction, so it springs instead of easing. Critically damped,
        /// no overshoot; `nil`-style RM fallback handled by callers choosing
        /// `reducedCrossFade`.
        static var pressFeedback: Animation {
            AccessibilityPreferences.reduceMotion
                ? reducedCrossFade
                : .interpolatingSpring(duration: 0.2, bounce: 0)
        }

        /// Countdown ticks (retry ring + numeric text) — critically damped, no bounce.
        static let countdownTick: Animation = .interpolatingSpring(duration: 0.3, bounce: 0)

        static var scrollAnimation: Animation? {
            AccessibilityPreferences.reduceMotion ? nil : contentCrossFade
        }

        /// Cross-fade for thinking→streaming transition.
        static var streamingTransition: Animation? {
            AccessibilityPreferences.reduceMotion ? nil : contentCrossFade
        }

        /// Streaming phase swaps (status row → thinking → streaming text →
        /// retry) — opacity plus a whisper of scale so the exchange reads as
        /// one continuous surface re-forming instead of paging. Scale doesn't
        /// affect layout, so scroll position is untouched. The plan skeleton
        /// keeps plain opacity: its exit is the matched-glass morph into the
        /// confirmed card, which is already the continuity.
        static var streamingPhase: AnyTransition {
            AccessibilityPreferences.reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.97))
        }

        static var expandAnimation: Animation? {
            AccessibilityPreferences.reduceMotion ? reducedCrossFade : expandCollapse
        }
    }

    /// Elapsed labels for long-running states. Silence for the first few
    /// seconds, then a count so long waits read as progress, not a freeze.
    enum Elapsed {
        static let graceSeconds = 5

        /// `nil` inside the grace window; "12s" under a minute; "3:07" after.
        static func label(_ seconds: Int) -> String? {
            guard seconds >= graceSeconds else { return nil }
            if seconds < 60 { return "\(seconds)s" }
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        }
    }

    enum Markdown {
        /// Collapsed assistant reply height before “Show more”.
        /// Slightly taller than before to match airier paragraph rhythm.
        static let collapsedReplyHeight: CGFloat = 320
        /// Code blocks taller than this show a collapse control.
        static let collapsedCodeLineLimit = 20
        /// Cheap gate before measuring full markdown height (avoids double layout on tiny replies).
        static let assistantMeasureCharacterGate = 400
        /// Tool results at or under this size start expanded.
        static let shortToolResultCharacterLimit = 180
        static let shortToolResultLineLimit = 2
        /// Approval-card preview clip limits — full arguments stay in the transcript.
        static let approvalContentClipLimit = 300
        static let approvalTextClipLimit = 600
        static let approvalPreviewLineLimit = 4
        /// Monospaced code font size (~85% of reading body, matching github-markdown `pre`).
        static let codeFontSize: CGFloat = 12
        /// Content padding — github-markdown uses 16; top is taller to clear floating chrome.
        static let codeBlockContentPadding: CGFloat = 16
        /// Extra top inset so the first line clears the floating language / copy chrome.
        static let codeBlockChromeClearance: CGFloat = 22
        /// Continuous corner radius aligned with github-markdown (6) + Apple continuous).
        static let codeBlockCornerRadius: CGFloat = 6
        /// Fold-fade mask heights — clipped content dissolves into the surface
        /// below instead of hitting a hard clip edge. Reading canvas is 14pt;
        /// chip / code density is 12pt.
        static let foldFadeHeight: CGFloat = 52
        static let chipFoldFadeHeight: CGFloat = 36

        /// Code point size for a Dynamic Type–scaled reading size.
        static func scaledCodeFontSize(readingSize: CGFloat) -> CGFloat {
            readingSize * (codeFontSize / Typography.readingSize)
        }

        /// Line height for fenced code, including theme `relativeLineSpacing(.em(0.25))` (~1.45).
        static func codeLineHeight(fontSize: CGFloat = codeFontSize) -> CGFloat {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let native = font.ascender - font.descender + font.leading
            return ceil(native * 1.45)
        }

        static func collapsedCodeContentHeight(
            lineLimit: Int = collapsedCodeLineLimit,
            fontSize: CGFloat = codeFontSize
        ) -> CGFloat {
            CGFloat(lineLimit) * codeLineHeight(fontSize: fontSize)
                + codeBlockContentPadding
                + codeBlockChromeClearance
                + codeBlockContentPadding
        }
    }

    enum Symbol {
        static let brand = "leaf.fill"
        static let returnKey = "return"
        static let settings = "gearshape"
        static let pending = "exclamationmark.circle.fill"
        static let stepPending = "circle"
        static let stepRunning = "circle.dotted"
        static let stepSuccess = "checkmark.circle.fill"
        static let stepFailed = "xmark.circle.fill"
        static let tools = "wrench.and.screwdriver"
        static let skills = "book.closed"
        static let skillSave = "tray.and.arrow.down"
        static let mcp = "server.rack"
    }
}

/// Discrete symbol effects (bounce/pulse) have no `isActive:` overload, so
/// Reduce Motion gating works by omitting the modifier entirely.
private struct SageDiscreteSymbolEffectModifier<T, V>: ViewModifier
where T: DiscreteSymbolEffect & SymbolEffect, V: Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let effect: T
    let value: V

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(effect, value: value)
        }
    }
}

extension View {
    func sageSymbolEffect<T, V>(
        _ effect: T,
        value: V
    ) -> some View where T: DiscreteSymbolEffect & SymbolEffect, V: Equatable {
        modifier(SageDiscreteSymbolEffectModifier(effect: effect, value: value))
    }

    /// Symbol replace transition gated on Reduce Motion — the one symbol
    /// animation `sageSymbolEffect` can't express (it's a content
    /// transition, not a discrete effect).
    @ViewBuilder
    func sageSubmitSymbolReplaceTransition() -> some View {
        if AccessibilityPreferences.reduceMotion {
            contentTransition(.identity)
        } else {
            contentTransition(.symbolEffect(.replace))
        }
    }

    /// Keyboard shortcut bound only when enabled — one Button definition can
    /// support shortcut-suppressed contexts without cloning branches.
    @ViewBuilder
    func sageShortcut(_ shortcut: KeyboardShortcut?, enabled: Bool) -> some View {
        if enabled, let shortcut {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }

    /// Hit slop so a small visual control reaches the comfortable 28pt
    /// target — padding and tappable shape grow together.
    func sageHitSlop(visualSize: CGFloat) -> some View {
        padding(max(0, (SageDesign.Control.minimumHitTarget - visualSize) / 2))
            .contentShape(Rectangle())
    }
}
