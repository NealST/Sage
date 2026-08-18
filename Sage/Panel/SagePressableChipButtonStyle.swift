//
//  SagePressableChipButtonStyle.swift
//  Sage
//

import SwiftUI

/// Instant press feedback — opacity always; scale only when Reduce Motion is off.
struct SagePressableChipButtonStyle: ButtonStyle {
    var emphasized: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color.primary.opacity(
                            configuration.isPressed ? 0.14 : (emphasized ? 0.10 : 0.06)
                        )
                    )
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : SageDesign.Motion.contentCrossFade,
                value: configuration.isPressed
            )
    }
}
