//
//  RetryCountdownView.swift
//  Sage
//

import SwiftUI

/// Displays a retry countdown with a circular progress indicator.
///
/// Apple design principles applied:
/// - **Continuous feedback** — the ring animates smoothly each second (spring, no hard jumps).
/// - **Status clarity** — shows attempt number and seconds remaining.
/// - **Reduced motion** — falls back to a simple text countdown without the ring animation.
/// - **Spatial consistency** — occupies the same slot as the "Thinking…" spinner.
struct RetryCountdownView: View {
    let state: RetryDisplayState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SageDesign.Spacing.sm) {
            countdownRing
            VStack(alignment: .leading, spacing: 2) {
                Text("Retrying in \(state.secondsRemaining)s")
                    .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(
                        reduceMotion ? .none : .interpolatingSpring(duration: 0.3, bounce: 0),
                        value: state.secondsRemaining
                    )
                Text("Attempt \(state.attempt) of \(state.maxAttempts)")
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Retrying, attempt \(state.attempt) of \(state.maxAttempts), \(state.secondsRemaining) seconds remaining")
    }

    private var countdownRing: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 2.5)

            // Progress arc — animates with a critically damped spring (no overshoot).
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    Color.orange.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .none : .interpolatingSpring(duration: 0.6, bounce: 0),
                    value: state.secondsRemaining
                )

            // Seconds number in center
            Text("\(state.secondsRemaining)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
                .contentTransition(.numericText())
                .animation(
                    reduceMotion ? .none : .interpolatingSpring(duration: 0.3, bounce: 0),
                    value: state.secondsRemaining
                )
        }
        .frame(width: 24, height: 24)
    }

    /// Progress from 0 (just started waiting) to 1 (about to retry).
    private var ringProgress: CGFloat {
        let total = CGFloat(max(state.totalSeconds, 1))
        let elapsed = total - CGFloat(state.secondsRemaining)
        return elapsed / total
    }
}
