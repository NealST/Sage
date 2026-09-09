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
        Section {
            Toggle(
                "Open Sage at login",
                isOn: Binding(
                    get: { openAtLogin },
                    set: { onToggle($0) }
                )
            )
            if SageLoginItem.needsApproval {
                Button("Allow in Login Items…") {
                    SageLoginItem.openLoginItemsSettings()
                }
            }
        } footer: {
            Text(
                loginItemHint ?? """
                Schedules only run while Sage is open. Turn this on so Sage launches at login.
                """
            )
        }
    }
}
