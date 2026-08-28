//
//  SettingsPrivacySection.swift
//  Sage
//

import SwiftUI

struct SettingsPrivacySection: View {
    var eraseMessage: String?
    var isBusy: Bool
    var onErase: () -> Void
    @State private var authorizationRefresh = 0

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
                        Shell, Skill, schedule, and MCP processes run in a default-deny macOS sandbox. \
                        Normal reads are automatic; sensitive reads and local writes require \
                        just-in-time approval. Shell network and protected-metadata access are also gated.
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
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Long-term permissions")
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    Text(longTermPermissionSummary)
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Revoke all") {
                    ToolAuthorizationGrantStore.shared.removeAllLongTermGrants()
                    authorizationRefresh += 1
                }
                .controlSize(.small)
                .disabled(ToolAuthorizationGrantStore.shared.longTermGrantCount == 0)
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

    private var longTermPermissionSummary: String {
        _ = authorizationRefresh
        let count = ToolAuthorizationGrantStore.shared.longTermGrantCount
        return count == 1 ? "1 permission is active." : "\(count) permissions are active."
    }
}
