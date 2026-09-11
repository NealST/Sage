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
/// - **Agency** — waiting is not being trapped: Stop is right here, Escape-bound.
/// - **Reduced motion** — falls back to a simple text countdown without the ring animation.
/// - **Spatial consistency** — occupies the same slot as the "Thinking…" spinner.
struct RetryCountdownView: View {
    let state: RetryDisplayState
    var onStop: (() -> Void)? = nil
    var onRetryNow: (() -> Void)? = nil

    @Environment(\.sageTypography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            countdownRing
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .sageFont(type.body, weight: .medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(
                        reduceMotion ? .none : SageDesign.Motion.countdownTick,
                        value: state.secondsRemaining
                    )
                Text("Attempt \(state.attempt) of \(state.maxAttempts)")
                    .sageFont(type.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if let onStop {
                Button(role: .cancel, action: onStop) {
                    Text("Stop")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .keyboardShortcut(.cancelAction)
                .help("Stop this turn instead of waiting for the next attempt (Esc)")
            }
            if let onRetryNow {
                Button(action: onRetryNow) {
                    Text("Retry Now")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .help("Skip the remaining wait and retry immediately")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    /// "Rate limited — retrying in 5s"; falls back to a bare countdown when
    /// the gateway didn't report a reason.
    var headline: String {
        guard let reason = state.reason?.nilIfEmpty else {
            return "Retrying in \(state.secondsRemaining)s"
        }
        return "\(reason) — retrying in \(state.secondsRemaining)s"
    }

    var accessibilityText: String {
        let countdown = "Retrying, attempt \(state.attempt) of \(state.maxAttempts), \(state.secondsRemaining) seconds remaining"
        guard let reason = state.reason?.nilIfEmpty else { return countdown }
        return "\(reason). \(countdown)"
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
                    SageDesign.Palette.warning.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? .none : SageDesign.Motion.countdownTick,
                    value: state.secondsRemaining
                )

            // Seconds number in center
            Text("\(state.secondsRemaining)")
                .sageMicro(type.micro, weight: .semibold, design: .rounded)
                .foregroundStyle(SageDesign.Palette.warning)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(
                    reduceMotion ? .none : SageDesign.Motion.countdownTick,
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
