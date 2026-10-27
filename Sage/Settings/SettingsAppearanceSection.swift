//
//  SettingsAppearanceSection.swift
//  Sage
//
//  General pane: app text size (macOS has no Dynamic Type channel).
//

import SwiftUI

struct SettingsAppearanceSection: View {
    @Environment(\.sageTypography) private var type

    var body: some View {
        Section {
            Picker("Text Size", selection: scaleBinding) {
                ForEach(SageTextSizeSettings.steps, id: \.self) { step in
                    Text(Self.label(for: step)).tag(step)
                }
            }
            .help("Enlarges interface and reading text across Sage's windows")
        } header: {
            Text("Appearance")
        } footer: {
            Text("Interface and reading text scale across all Sage windows.")
        }
    }

    /// Reading the shared scale through the binding during body evaluation
    /// registers the Observation dependency, so menu-shortcut changes (⌘+/⌘-)
    /// refresh this picker live.
    private var scaleBinding: Binding<CGFloat> {
        Binding(
            get: { SageTextSizeSettings.shared.scale },
            set: { SageTextSizeSettings.shared.setScale($0) }
        )
    }

    private static func label(for step: CGFloat) -> String {
        step == 1.0 ? "Default" : "\(Int((step * 100).rounded()))%"
    }
}
