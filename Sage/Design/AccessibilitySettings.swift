//
//  AccessibilitySettings.swift
//  Sage
//
//  Live system accessibility options for SwiftUI observation.
//

import AppKit
import SwiftUI

@MainActor
@Observable
final class AccessibilitySettings {
    static let shared = AccessibilitySettings()

    private(set) var reduceMotion: Bool
    private(set) var reduceTransparency: Bool
    private(set) var increaseContrast: Bool
    private(set) var voiceOverEnabled: Bool
    /// Bumps when any flag changes — handy for `animation(_:value:)` / forced refresh.
    private(set) var revision: Int = 0

    private var observer: NSObjectProtocol?

    private init() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        voiceOverEnabled = NSWorkspace.shared.isVoiceOverEnabled
        observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AccessibilitySettings.shared.refresh()
            }
        }
    }

    func refresh() {
        let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        guard motion != reduceMotion
            || transparency != reduceTransparency
            || contrast != increaseContrast
            || voiceOver != voiceOverEnabled
        else { return }
        reduceMotion = motion
        reduceTransparency = transparency
        increaseContrast = contrast
        voiceOverEnabled = voiceOver
        revision &+= 1
    }

    // MARK: - Chrome opacities (contrast-aware)

    var fillOpacity: Double { increaseContrast ? 0.14 : 0.06 }
    var strongFillOpacity: Double { increaseContrast ? 0.20 : 0.10 }
    var pillFillOpacity: Double { increaseContrast ? 0.16 : 0.08 }
    var strokeOpacity: Double { increaseContrast ? 0.40 : 0.10 }
    var dividerOpacity: Double { increaseContrast ? 0.60 : 0.35 }
}
