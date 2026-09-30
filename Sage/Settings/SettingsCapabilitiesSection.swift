//
//  SettingsCapabilitiesSection.swift
//  Sage
//

import SwiftUI

struct SettingsCapabilitiesSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sageTypography) private var type
    @Bindable var settings: ModelSettings
    @Binding var pinnedSkillsSession: AgentSession?
    @Binding var showMCPManage: Bool
    @Binding var showSkillsManage: Bool
    @State private var mutedTipKinds: Set<SkillTipKind> = []

    var body: some View {
        Section {
            Toggle("Codex execute loop", isOn: $settings.useHarnessRunTurn)
                .help("Sample Execute turns through the Codex runTurn loop. Tool approval still uses the HUD cards.")
        } footer: {
            Text("Uses Codex compact, MCP startup, and guardian gates. Applies to new agent windows. Turn this off to go back to the previous Execute loop.")
        }

        Section {
            Button {
                let session = pinnedSkillsSession ?? appState.keySession
                pinnedSkillsSession = session
                showSkillsManage = true
            } label: {
                LabeledContent("Skills") {
                    HStack(spacing: SageDesign.Spacing.small) {
                        Text("\(enabledSkillCount) of \(skillsCatalog.skills.count) enabled")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        navigationChevron
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(Array(skillsCatalog.skills.prefix(4))) { skill in
                Toggle(
                    skill.name,
                    isOn: Binding(
                        get: {
                            skillsCatalog.skills.first { $0.name == skill.name }?.enabled
                                ?? skill.enabled
                        },
                        set: { enabled in
                            let session = pinnedSkillsSession ?? appState.keySession
                            session.skillCatalog.setSkillEnabled(skill, enabled: enabled)
                            Task { await appState.syncSkillEnablement(from: session) }
                        }
                    )
                )
            }

            if skillsCatalog.skills.count > 4 {
                Button {
                    let session = pinnedSkillsSession ?? appState.keySession
                    pinnedSkillsSession = session
                    showSkillsManage = true
                } label: {
                    Text("Show All \(skillsCatalog.skills.count) Skills…")
                        .monospacedDigit()
                }
            }

            Button {
                showMCPManage = true
            } label: {
                LabeledContent("MCP Servers") {
                    HStack(spacing: SageDesign.Spacing.small) {
                        Text("Full-trust · \(connectedMCPCount) connected")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        navigationChevron
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(Array(appState.mcpHub.mcpServers.prefix(3))) { server in
                Toggle(
                    server.name,
                    isOn: Binding(
                        get: {
                            appState.mcpHub.mcpServers.first { $0.id == server.id }?.enabled
                                ?? server.enabled
                        },
                        set: { appState.mcpHub.setMCPEnabled(server.id, enabled: $0) }
                    )
                )
            }

            if appState.mcpHub.mcpServers.count > 3 {
                Button {
                    showMCPManage = true
                } label: {
                    Text("Show All \(appState.mcpHub.mcpServers.count) Servers…")
                        .monospacedDigit()
                }
            }
        } footer: {
            if !mutedTipKinds.isEmpty {
                VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
                    Text("Sage won’t suggest: \(mutedTipNames).")
                    Button("Restore All Suggestions") {
                        SkillTipMuting.reset()
                        mutedTipKinds = []
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            mutedTipKinds = SkillTipMuting.mutedKinds
        }
    }

    private var mutedTipNames: String {
        SkillTipKind.allCases
            .filter { mutedTipKinds.contains($0) }
            .map(\.suggestionName)
            .joined(separator: ", ")
    }

    /// Rows that open another surface get the standard trailing chevron.
    private var navigationChevron: some View {
        Image(systemName: "chevron.right")
            .sageFont(type.icon, weight: .semibold)
            .foregroundStyle(.tertiary)
    }

    private var skillsCatalog: SkillCatalog {
        (pinnedSkillsSession ?? appState.keySession).skillCatalog
    }

    private var enabledSkillCount: Int {
        skillsCatalog.skills.count(where: \.enabled)
    }

    private var connectedMCPCount: Int {
        appState.mcpHub.mcpServers.count { $0.status == .connected }
    }
}
