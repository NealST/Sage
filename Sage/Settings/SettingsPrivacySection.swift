//
//  SettingsPrivacySection.swift
//  Sage
//

import SwiftUI

struct SettingsPrivacySection: View {
    var eraseMessage: String?
    var isBusy: Bool
    var onErase: () -> Void

    var body: some View {
        SettingsFormChrome.section("Privacy") {
            HStack(spacing: SageDesign.Spacing.medium) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local history")
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    Text(eraseMessage ?? "Task events stay on this Mac.")
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(
                            eraseMessage?.hasPrefix("Could") == true ? Color.orange : Color.secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Erase…") {
                    onErase()
                }
                .controlSize(.small)
                .disabled(isBusy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .sagePanelBackground(cornerRadius: 10)
        }
    }
}
