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
        SettingsFormChrome.section("Capabilities") {
            VStack(spacing: 0) {
                SettingsFormChrome.capabilityRow(
                    symbol: SageDesign.Symbol.skills,
                    title: "Skills",
                    detail: "\(enabledSkillCount) of \(skillsCatalog.skills.count) enabled",
                    isFirst: true
                ) {
                        let session = pinnedSkillsSession ?? appState.keySession
                        pinnedSkillsSession = session
                        onOpenSkills?(session)
                }

                ForEach(Array(skillsCatalog.skills.prefix(4).enumerated()), id: \.element.id) { _, skill in
                    SettingsFormChrome.divider
                    SettingsFormChrome.quickToggleRow(
                        title: skill.name,
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

                SettingsFormChrome.divider

                SettingsFormChrome.capabilityRow(
                    symbol: SageDesign.Symbol.mcp,
                    title: "MCP Servers",
                    detail: "Full-trust extensions · \(connectedMCPCount) connected",
                    isLast: appState.mcpHub.mcpServers.isEmpty
                ) { showMCPManage = true }

                ForEach(Array(appState.mcpHub.mcpServers.prefix(3).enumerated()), id: \.element.id) { index, server in
                    SettingsFormChrome.divider
                    SettingsFormChrome.quickToggleRow(
                        title: server.name,
                        detail: mcpStatusDetail(server),
                        isLast: index == min(2, appState.mcpHub.mcpServers.count - 1),
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
            .sagePanelBackground(cornerRadius: 10)
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

    private func mcpStatusDetail(_ server: MCPServerConfig) -> String? {
        switch server.status {
        case .connected: return nil
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .error: return server.statusMessage ?? "Error"
        case .disconnected: return server.enabled ? "Disconnected" : nil
        case .disabled: return nil
        }
    }
}
