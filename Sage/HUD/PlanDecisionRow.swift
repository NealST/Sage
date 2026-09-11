//
//  PlanDecisionRow.swift
//  Sage
//
//  Decision rows shared by the confirmation cards so the safety-critical
//  pairs can't drift. Every card speaks the same button vocabulary:
//  secondary = system glass (Escape), primary = prominent glass (Return) —
//  shortcuts suppressed while another surface owns the keyboard.
//

import SwiftUI

struct PlanDecisionRow: View {
    var onConfirm: () -> Void
    var onCancel: () -> Void
    /// Bind Return / Escape only when no other surface owns them.
    var bindsShortcuts: Bool

    var body: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Button(role: .cancel, action: onCancel) {
                Text("Cancel")
            }
            .sageShortcut(.cancelAction, enabled: bindsShortcuts)
            .buttonStyle(.glass)
            .controlSize(.regular)

            Spacer(minLength: 0)

            Button("Run", action: onConfirm)
                .sageShortcut(.defaultAction, enabled: bindsShortcuts)
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
        }
        .padding(.top, SageDesign.Spacing.extraSmall)
    }
}

/// The escape hatch while a plan executes — one Stop, right-aligned, Escape
/// bound. Shared by both plan cards so stopping reads the same everywhere.
struct PlanStopRow: View {
    var bindsShortcuts: Bool
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Spacer(minLength: 0)
            Button("Stop", role: .cancel, action: onStop)
                .sageShortcut(.cancelAction, enabled: bindsShortcuts)
                .buttonStyle(.glass)
                .controlSize(.regular)
        }
        .padding(.top, SageDesign.Spacing.extraSmall)
    }
}
