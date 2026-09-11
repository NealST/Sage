//
//  DashboardView.swift
//  Sage
//
//  Runtime status dashboard — session tokens and MCP.
//  Designed as a live monitoring panel, separate from configuration (Settings).
//

import SwiftUI
import UserNotifications

struct DashboardView: View {
    @Environment(AppState.self) var appState
    @Environment(\.sageTypography) var type
    @State var notificationsDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SageDesign.Spacing.extraLarge) {
                        schedulesSection
                        mcpServersSection
                        tokenUsageSection
                    }
                    .padding(.horizontal, SageDesign.Spacing.extraLarge)
                    .padding(.top, 20)
                    .padding(.bottom, SageDesign.Spacing.large)
                }
                .sageScrollEdgeGlass()
                .onAppear {
                    // First paint jumps instantly — content is still settling in.
                    if let id = appState.focusedScheduleID {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: appState.focusedScheduleID) { _, id in
                    // A notification click while the Dashboard is already open
                    // should glide to the row, not teleport.
                    guard let id else { return }
                    if let animation = SageDesign.Motion.streamingScroll {
                        withAnimation(animation) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    } else {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(minWidth: 360)
        .frame(minHeight: 360)
        .task {
            await appState.schedules.reload()
            notificationsDenied = await Self.notificationPermissionDenied
        }
    }

    /// ScheduleNotifier.post stays silent when permission is denied, so the
    /// Dashboard is the only place that can surface it.
    private static var notificationPermissionDenied: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .denied
        }
    }

    // MARK: - Token Usage

    private var tokenUsageSection: some View {
        dashboardSection("Task Tokens") {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Task")
                            .sageFont(type.body, weight: .medium)
                        Text(tokenSummary)
                            .sageFont(type.caption, design: .monospaced)
                            .foregroundStyle(.secondary)
                    }
                    .help("Tokens billed in this task. Start Fresh resets the counter.")
                    Spacer()
                }
                if let occupancy = appState.agent.state.contextOccupancy {
                    contextBudgetBar(occupancy)
                } else {
                    // Nil before the first prompt assembles — a live tile with
                    // a quiet inline note, not an empty-state page.
                    Text("Context fill appears after the first turn.")
                        .sageMicro(type.micro)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(SageDesign.Spacing.medium)
            .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
        }
    }

    /// How full the live conversation's context window is — the signal for
    /// "when should I Start Fresh". Occupancy comes from the last assembled
    /// execute prompt, so it self-corrects after auto-compaction.
    private func contextBudgetBar(_ occupancy: Double) -> some View {
        let percent = Int((occupancy * 100).rounded())
        let isHigh = occupancy >= 0.8
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Context")
                    .sageMicro(type.micro, weight: .medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isHigh ? "\(percent)% — consider starting fresh" : "\(percent)% of window")
                    .sageMicro(type.micro)
                    .foregroundStyle(isHigh ? SageDesign.Palette.warning : .secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(SageDesign.Chrome.pillFillOpacity))
                    Capsule(style: .continuous)
                        .fill(isHigh ? SageDesign.Palette.warning : Color.accentColor)
                        .frame(width: max(geo.size.width * occupancy, 4))
                }
            }
            .frame(height: 4)
        }
        .help("How full the live task's context window is. Start Fresh frees the window.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context window")
        .accessibilityValue("\(percent) percent full")
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
                    .sageFont(type.caption)
                    .foregroundStyle(.secondary)
                if servers.isEmpty {
                    VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No servers configured")
                                .sageFont(type.body, weight: .medium)
                            Text("MCP servers add tools like web search or docs to every project.")
                                .sageFont(type.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Add MCP Server…") {
                            NotificationCenter.default.post(
                                name: .sageOpenSettingsMCP,
                                object: nil
                            )
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular)
                    }
                    .padding(SageDesign.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
                } else {
                    GlassEffectContainer(spacing: SageDesign.Glass.containerSpacing) {
                        VStack(spacing: SageDesign.Spacing.small) {
                            ForEach(servers, id: \.id) { server in
                                MCPServerRow(server: server) {
                                    appState.mcpHub.retryServer(server.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(SageDesign.Spacing.medium)
        }
    }
}
