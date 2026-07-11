//
//  AccessibilityPreferences.swift
//  Sage
//

import AppKit
import SwiftUI

enum AccessibilityPreferences {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}

/// Shared HUD chrome that respects Reduce Transparency / Increase Contrast.
struct SageMaterialBackground: View {
    var cornerRadius: CGFloat = SageDesign.HUD.cornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if AccessibilityPreferences.reduceTransparency || AccessibilityPreferences.increaseContrast {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.ultraThinMaterial)
            }

            if AccessibilityPreferences.increaseContrast {
                shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
            } else if !AccessibilityPreferences.reduceTransparency {
                // Single light catch on the top edge — not a full outline card stroke.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.06),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
        }
    }
}
