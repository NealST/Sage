//
//  SkillsManageView.swift
//  Sage
//

import SwiftUI

struct SkillsManageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedName: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Skills")
                    .font(.headline)
                Spacer()
                Button("Open Folder") {
                    appState.capabilities.openSkillsFolder()
                }
                Button("Refresh") {
                    Task { await appState.capabilities.reloadSkills() }
                }
            }
            .padding()

            Divider()

            List(selection: $selectedName) {
                ForEach(appState.capabilities.skills) { skill in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(skill.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Text(skill.sourceLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle(
                            "Enabled",
                            isOn: Binding(
                                get: { skill.enabled },
                                set: { appState.capabilities.setSkillEnabled(skill.name, enabled: $0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .tag(skill.name)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)

            if let selectedName,
               let selected = appState.capabilities.skills.first(where: { $0.name == selectedName }) {
                Divider()
                ScrollView {
                    Text(SkillRegistry.readBody(for: selected, limit: 6_000))
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .frame(height: 160)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 480)
    }
}
