//
//  SettingsSchedulesSection.swift
//  Sage
//

import SwiftUI

struct SettingsSchedulesSection: View {
    @Binding var openAtLogin: Bool
    var loginItemHint: String?
    var onToggle: (Bool) -> Void

    var body: some View {
        SettingsFormChrome.section("Schedules") {
            VStack(spacing: 0) {
                SettingsFormChrome.quickToggleRow(
                    title: "Open Sage at login",
                    detail: loginItemHint ?? """
                    Schedules only run while Sage is open. Turn this on so Sage launches at login.
                    """,
                    isLast: !SageLoginItem.needsApproval,
                    isOn: Binding(
                        get: { openAtLogin },
                        set: { onToggle($0) }
                    )
                )
                if SageLoginItem.needsApproval {
                    SettingsFormChrome.divider
                    Button {
                        SageLoginItem.openLoginItemsSettings()
                    } label: {
                        HStack {
                            Text("Allow in Login Items…")
                                .font(.system(size: SageDesign.Typography.bodySize))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sagePanelBackground(cornerRadius: 10)
        }
    }
}
