//
//  SettingsPrivacySection.swift
//  Sage
//

import SwiftUI

struct SettingsPrivacySection: View {
    @Environment(AppState.self) private var appState
    var eraseMessage: String?
    var isBusy: Bool
    var onErase: () -> Void
    @State private var authorizationRefresh = 0
    @State private var showEraseConfirm = false

    var body: some View {
        Section {
            Text(
                """
                File tools stay in your home folder, or the project root when a Project is focused. \
                Shell, Skill, schedule, and MCP processes run in a default-deny macOS sandbox. \
                Normal reads are automatic; sensitive reads and local writes require \
                just-in-time approval.
                """
            )
            .foregroundStyle(.secondary)
        } header: {
            Text("Sandbox")
        }

        if !longTermPermissionSummaries.isEmpty {
            Section("Permissions") {
                ForEach(longTermPermissionSummaries) { grant in
                    LabeledContent(grant.title) {
                        Button("Revoke") {
                            ToolAuthorizationGrantStore.shared.removeLongTermGrant(id: grant.id)
                            authorizationRefresh += 1
                        }
                        .controlSize(.small)
                    }
                    Text(grant.detail)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }

        Section {
            LabeledContent("Long-term permissions") {
                Button("Revoke all") {
                    ToolAuthorizationGrantStore.shared.removeAllLongTermGrants()
                    authorizationRefresh += 1
                }
                .controlSize(.small)
                .disabled(ToolAuthorizationGrantStore.shared.longTermGrantCount == 0)
            }
            Text(longTermPermissionSummary)
                .foregroundStyle(.secondary)

            LabeledContent("Local history") {
                Button("Erase…") {
                    showEraseConfirm = true
                }
                .controlSize(.small)
                .disabled(isBusy)
                .confirmationDialog(
                    eraseDialogTitle,
                    isPresented: $showEraseConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Erase Data", role: .destructive, action: onErase)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(eraseDialogMessage)
                }
            }
            Text(eraseMessage ?? "Task events stay on this Mac.")
                .foregroundStyle(
                    eraseMessage?.hasPrefix("Could") == true ? Color.orange : Color.secondary
                )
        }
    }

    private var eraseDialogTitle: String {
        if case .awaitingConfirmation = appState.agent.state.phase {
            return "Erase data and abandon pending plan?"
        }
        return "Erase all local Sage data?"
    }

    private var eraseDialogMessage: String {
        if case .awaitingConfirmation = appState.agent.state.phase {
            return "This deletes local task history and abandons the pending plan. Your API key in Keychain is kept."
        }
        return "This permanently deletes local task history from this Mac. Your API key in Keychain is kept."
    }

    private var longTermPermissionSummary: String {
        _ = authorizationRefresh
        let count = ToolAuthorizationGrantStore.shared.longTermGrantCount
        return count == 1 ? "1 permission is active." : "\(count) permissions are active."
    }

    private var longTermPermissionSummaries: [ToolAuthorizationGrantSummary] {
        _ = authorizationRefresh
        return ToolAuthorizationGrantStore.shared.longTermGrantSummaries
    }
}
