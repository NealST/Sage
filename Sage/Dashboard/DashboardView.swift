//
//  DashboardView.swift
//  Sage
//
//  Runtime status dashboard — session tokens and MCP.
//  Designed as a live monitoring panel, separate from configuration (Settings).
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SageDesign.Spacing.xl) {
                    tokenUsageSection
                    mcpServersSection
                }
                .padding(.horizontal, SageDesign.Spacing.xl)
                .padding(.top, 20)
                .padding(.bottom, SageDesign.Spacing.lg)
            }
        }
        .frame(width: 400)
        .frame(minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
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
            .padding(SageDesign.Spacing.md)
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
            if servers.isEmpty {
                Text("No servers configured")
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .foregroundStyle(.tertiary)
                    .padding(SageDesign.Spacing.md)
            } else {
                VStack(spacing: SageDesign.Spacing.sm) {
                    ForEach(servers, id: \.id) { server in
                        MCPServerRow(server: server) {
                            appState.mcpHub.retryServer(server.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTokenCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        let k = Double(count) / 1000
        return String(format: "%.1fk", k)
    }

    // MARK: - Section Builder

    private func dashboardSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Text(title)
                .font(.system(size: SageDesign.Typography.captionSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - MCP Server Row

private struct MCPServerRow: View {
    let server: MCPServerConfig
    let onRetry: () -> Void
    @State private var logsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: SageDesign.Spacing.sm) {
                Circle()
                    .fill(serverStatusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(server.name)
                    .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    .lineLimit(1)
                    .accessibilityLabel("\(server.name), \(serverStatusAccessibilityName)")

                Spacer()

                if server.status == .error || server.status == .reconnecting {
                    Button("Retry") { onRetry() }
                        .controlSize(.small)
                }

                if !server.recentLogs.isEmpty {
                    Button(logsExpanded ? "Hide logs" : "Show logs", systemImage: "chevron.right") {
                        withAnimation(SageDesign.Motion.contentCrossFade) {
                            logsExpanded.toggle()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(logsExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: logsExpanded)
                }
            }

            // Status subtitle
            if let message = server.statusMessage {
                Text(message)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8 + SageDesign.Spacing.sm) // align with name
                    .padding(.top, 2)
                    .contentTransition(.opacity)
            }

            // Expandable logs
            if logsExpanded && !server.recentLogs.isEmpty {
                ScrollView(.vertical) {
                    Text(server.recentLogs.joined(separator: "\n"))
                        .font(.system(size: SageDesign.Typography.microSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(.top, SageDesign.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(SageDesign.Spacing.md)
        .sagePanelBackground(cornerRadius: 10)
        .animation(SageDesign.Motion.contentCrossFade, value: server.status)
    }

    private var serverStatusColor: Color {
        switch server.status {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .error: .red
        case .disabled, .disconnected: Color.secondary
        }
    }

    private var serverStatusAccessibilityName: String {
        switch server.status {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .error: "Error"
        case .disconnected: "Disconnected"
        case .disabled: "Disabled"
        }
    }
}
