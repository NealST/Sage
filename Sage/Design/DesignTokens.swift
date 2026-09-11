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
    }

    /// Persistent agent workspace window.
    enum Panel {
        static let width: CGFloat = 760
        static let height: CGFloat = 580
        /// Single unified titlebar row (aligns with traffic lights).
        static let titlebarContentHeight: CGFloat = 52
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
        static var diffFillOpacity: Double { AccessibilitySettings.shared.diffFillOpacity }
        @MainActor
        static var strokeOpacity: Double { AccessibilitySettings.shared.strokeOpacity }
        @MainActor
        static var dividerOpacity: Double { AccessibilitySettings.shared.dividerOpacity }
    }

    /// Semantic colors — one meaning each so error treatments never drift.
    /// Warnings and transient attention states (awaiting confirmation, retrying,
    /// connecting, budget low) stay orange; `danger` is for failures only.
    /// `success` covers completions and diff insertions (green = added).
    nonisolated enum Palette {
        static let danger = Color(nsColor: .systemRed)
        static let warning = Color(nsColor: .systemOrange)
        static let success = Color(nsColor: .systemGreen)
    }

    enum Motion {
        static let contentCrossFade: Animation = .easeOut(duration: 0.18)
        static let reducedCrossFade: Animation = .easeOut(duration: 0.12)

        /// Window-level alpha fades (AppKit, seconds). Short on purpose —
        /// showing a window must stay effectively instant.
        static let windowFadeInDuration: TimeInterval = 0.18
        static let windowFadeOutDuration: TimeInterval = 0.15

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
        /// threshold would otherwise produce an extreme kick).
        static func dragSettle(velocity: CGFloat, from current: CGFloat) -> Animation? {
            guard !AccessibilityPreferences.reduceMotion else { return nil }
            let displacement = -current
            guard abs(displacement) > 0.5 else { return dragSettle }
            let normalized = (Double(velocity) * 0.3) / Double(displacement)
            let clamped = min(max(normalized, -2), 2)
            return .interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: clamped)
        }

        /// Brief settle after copy confirmation.
        static let copiedFeedback: Animation = .interpolatingSpring(duration: 0.28, bounce: 0)

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

        static var expandAnimation: Animation? {
            AccessibilityPreferences.reduceMotion ? reducedCrossFade : expandCollapse
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
    func sageShortcut(_ shortcut: KeyboardShortcut, enabled: Bool) -> some View {
        if enabled {
            keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
