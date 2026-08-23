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
            HStack(alignment: .top, spacing: SageDesign.Spacing.medium) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sandbox")
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    Text(
                        """
                        File tools stay in your home folder, or the project root when a Project is focused. \
                        Shell commands can still cd or redirect outside that folder.
                        """
                    )
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .sagePanelBackground(cornerRadius: 10)

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
