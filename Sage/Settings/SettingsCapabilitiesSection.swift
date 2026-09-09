//
//  SettingsCapabilitiesSection.swift
//  Sage
//

import SwiftUI

struct SettingsCapabilitiesSection: View {
    @Environment(AppState.self) private var appState
    @Binding var pinnedSkillsSession: AgentSession?
    @Binding var showMCPManage: Bool
    var onOpenSkills: ((AgentSession) -> Void)?

    var body: some View {
        Section {
            Button {
                let session = pinnedSkillsSession ?? appState.keySession
                pinnedSkillsSession = session
                onOpenSkills?(session)
            } label: {
                LabeledContent("Skills") {
                    Text("\(enabledSkillCount) of \(skillsCatalog.skills.count) enabled")
                        .foregroundStyle(.secondary)
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

            Button {
                showMCPManage = true
            } label: {
                LabeledContent("MCP Servers") {
                    Text("Full-trust · \(connectedMCPCount) connected")
                        .foregroundStyle(.secondary)
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
        }
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
