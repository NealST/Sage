//
//  DesignTokens.swift
//  Sage
//

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
    enum Chrome {
        static var fillOpacity: Double {
            AccessibilityPreferences.increaseContrast ? 0.14 : 0.06
        }

        static var strongFillOpacity: Double {
            AccessibilityPreferences.increaseContrast ? 0.20 : 0.10
        }

        static var pillFillOpacity: Double {
            AccessibilityPreferences.increaseContrast ? 0.16 : 0.08
        }

        static var strokeOpacity: Double {
            AccessibilityPreferences.increaseContrast ? 0.40 : 0.10
        }

        static var dividerOpacity: Double {
            AccessibilityPreferences.increaseContrast ? 0.60 : 0.35
        }
    }

    enum Motion {
        static let contentCrossFade: Animation = .easeOut(duration: 0.18)
        static let reducedCrossFade: Animation = .easeOut(duration: 0.12)

        static var scrollAnimation: Animation? {
            AccessibilityPreferences.reduceMotion ? nil : contentCrossFade
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
        static let mcp = "server.rack"
    }
}
