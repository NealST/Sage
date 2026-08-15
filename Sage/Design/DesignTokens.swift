//
//  DesignTokens.swift
//  Sage
//

import AppKit
import SwiftUI

enum SageDesign {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
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
        static let captionSize: CGFloat = 12
        static let titleSize: CGFloat = 15
        static let microSize: CGFloat = 11
        static let iconSize: CGFloat = 10
    }

    /// Contrast-aware surface opacities for fills, strokes, and dividers.
    /// Prefer `@Environment(AccessibilitySettings.self)` in views so values refresh live.
    enum Chrome {
        @MainActor static var fillOpacity: Double { AccessibilitySettings.shared.fillOpacity }
        @MainActor static var strongFillOpacity: Double { AccessibilitySettings.shared.strongFillOpacity }
        @MainActor static var pillFillOpacity: Double { AccessibilitySettings.shared.pillFillOpacity }
        @MainActor static var strokeOpacity: Double { AccessibilitySettings.shared.strokeOpacity }
        @MainActor static var dividerOpacity: Double { AccessibilitySettings.shared.dividerOpacity }
    }

    enum Motion {
        static let contentCrossFade: Animation = .easeOut(duration: 0.18)
        static let reducedCrossFade: Animation = .easeOut(duration: 0.12)

        /// Breathing cursor pulse — easeInOut for organic feel, not a hard blink.
        static let cursorPulse: Animation = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)

        /// Critically damped spring for streaming scroll — no overshoot, smooth settle.
        static let streamingScroll: Animation = .interpolatingSpring(duration: 0.3, bounce: 0)

        /// Expand/collapse (tool results, Show more) — critically damped, no bounce.
        static let expandCollapse: Animation = .interpolatingSpring(duration: 0.32, bounce: 0)

        /// Brief settle after copy confirmation.
        static let copiedFeedback: Animation = .interpolatingSpring(duration: 0.28, bounce: 0)

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
        /// Monospaced code font size (~85% of 14pt body, matching github-markdown `pre`).
        static let codeFontSize: CGFloat = 12
        /// Content padding — github-markdown uses 16; top is taller to clear floating chrome.
        static let codeBlockContentPadding: CGFloat = 16
        /// Extra top inset so the first line clears the floating language / copy chrome.
        static let codeBlockChromeClearance: CGFloat = 22
        /// Continuous corner radius aligned with github-markdown (6) + Apple continuous).
        static let codeBlockCornerRadius: CGFloat = 6

        /// Line height for fenced code, including theme `relativeLineSpacing(.em(0.25))` (~1.45).
        static var codeLineHeight: CGFloat {
            let font = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
            let native = font.ascender - font.descender + font.leading
            return ceil(native * 1.45)
        }

        static func collapsedCodeContentHeight(lineLimit: Int = collapsedCodeLineLimit) -> CGFloat {
            CGFloat(lineLimit) * codeLineHeight
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
