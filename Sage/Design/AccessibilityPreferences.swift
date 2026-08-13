//
//  AccessibilityPreferences.swift
//  Sage
//
//  Convenience accessors over live `AccessibilitySettings`. Prefer
//  `@Environment(AccessibilitySettings.self)` in SwiftUI views so changes refresh.
//

import AppKit

enum AccessibilityPreferences {
    @MainActor
    static var reduceMotion: Bool {
        AccessibilitySettings.shared.reduceMotion
    }

    @MainActor
    static var reduceTransparency: Bool {
        AccessibilitySettings.shared.reduceTransparency
    }

    @MainActor
    static var increaseContrast: Bool {
        AccessibilitySettings.shared.increaseContrast
    }
}
