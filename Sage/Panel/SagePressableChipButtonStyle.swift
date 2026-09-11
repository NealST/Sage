//
//  SagePressableChipButtonStyle.swift
//  Sage
//

import SwiftUI

/// Instant press feedback — glass capsule; scale only when Reduce Motion is off.
struct SagePressableChipButtonStyle: ButtonStyle {
    var emphasized: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AccessibilitySettings.self) private var accessibility

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return Group {
            if accessibility.reduceTransparency {
                configuration.label
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                Color.primary.opacity(
                                    pressed ? 0.14 : (emphasized ? 0.10 : 0.06)
                                )
                            )
                    }
            } else {
                configuration.label
                    .glassEffect(.clear.interactive(), in: .capsule)
            }
        }
        .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
        .animation(SageDesign.Motion.pressFeedback, value: pressed)
    }
}
