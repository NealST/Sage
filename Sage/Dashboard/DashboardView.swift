//
//  DashboardView.swift
//  Sage
//
//  Runtime status dashboard — session tokens and MCP.
//  Designed as a live monitoring panel, separate from configuration (Settings).
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SageDesign.Spacing.extraLarge) {
                        tokenUsageSection
                        mcpServersSection
                        schedulesSection
                    }
                    .padding(.horizontal, SageDesign.Spacing.extraLarge)
                    .padding(.top, 20)
                    .padding(.bottom, SageDesign.Spacing.large)
                }
                .onAppear {
                    if let id = appState.focusedScheduleID {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: appState.focusedScheduleID) { _, id in
                    if let id {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 400)
        .frame(minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await appState.schedules.reload()
        }
    }

    // MARK: - Token Usage

    private var tokenUsageSection: some View {
        dashboardSection("Session Tokens") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Session")
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    Text(tokenSummary)
                        .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(SageDesign.Spacing.medium)
            .sagePanelBackground(cornerRadius: 10)
        }
    }

    private var tokenSummary: String {
        let usage = appState.agent.state.tokenUsage
        return "In: \(formatTokenCount(usage.input)) • Out: \(formatTokenCount(usage.output))"
    }

    // MARK: - MCP Servers

    private var mcpServersSection: some View {
        dashboardSection("MCP Servers") {
            let servers = appState.mcpHub.mcpServers
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                Text("MCP tools are full-trust: they are not limited to the project sandbox.")
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .foregroundStyle(.secondary)
                if servers.isEmpty {
                    Text("No servers configured")
                        .font(.system(size: SageDesign.Typography.captionSize))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, SageDesign.Spacing.small)
                } else {
                    VStack(spacing: SageDesign.Spacing.small) {
                        ForEach(servers, id: \.id) { server in
                            MCPServerRow(server: server) {
                                appState.mcpHub.retryServer(server.id)
                            }
                        }
                    }
                }
            }
            .padding(SageDesign.Spacing.medium)
        }
    }
}
