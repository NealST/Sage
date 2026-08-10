//
//  DashboardView.swift
//  Sage
//
//  Runtime status dashboard — model state, memory usage, token consumption.
//  Designed as a live monitoring panel, separate from configuration (Settings).
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var modelStatus: LocalModelService.Status = .idle
    @State private var memoryBytes: Int = 0
    @State private var pressureLevel: MemoryPressureMonitor.PressureLevel = .normal
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SageDesign.Spacing.xl) {
                    localModelSection
                    memorySection
                    tokenUsageSection
                    mcpServersSection
                }
                .padding(.horizontal, SageDesign.Spacing.xl)
                .padding(.top, 20)
                .padding(.bottom, SageDesign.Spacing.lg)
            }
        }
        .frame(width: 400, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await refreshModelState() }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    // MARK: - Local Model

    private var localModelSection: some View {
        dashboardSection("Local Model") {
            VStack(spacing: SageDesign.Spacing.md) {
                HStack(spacing: SageDesign.Spacing.sm) {
                    statusDot
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                            .contentTransition(.opacity)
                        Text(statusSubtitle)
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    modelActionButton
                }
                .animation(SageDesign.Motion.contentCrossFade, value: statusColorKey)

                if case .downloading(let progress) = modelStatus {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }
            .padding(SageDesign.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(SageDesign.Chrome.strokeOpacity),
                        lineWidth: AccessibilityPreferences.increaseContrast ? 1 : 0.5
                    )
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .animation(.easeInOut(duration: 0.3), value: statusColorKey)
    }

    private var statusColor: Color {
        switch modelStatus {
        case .ready: .green
        case .loading, .downloading: .orange
        case .failed: .red
        case .idle, .unloadedByPressure: .secondary
        }
    }

    private var statusColorKey: Int {
        switch modelStatus {
        case .ready: 0
        case .loading, .downloading: 1
        case .failed: 2
        case .idle, .unloadedByPressure: 3
        }
    }

    private var statusTitle: String {
        switch modelStatus {
        case .idle: "Idle"
        case .downloading: "Downloading…"
        case .loading: "Loading…"
        case .ready: "Ready"
        case .failed: "Failed"
        case .unloadedByPressure: "Unloaded (Memory Pressure)"
        }
    }

    private var statusSubtitle: String {
        switch modelStatus {
        case .idle: "Model not loaded"
        case .downloading(let p): "Progress: \(Int(p * 100))%"
        case .loading: "Loading model into memory…"
        case .ready: "Qwen3-0.6B-4bit • \(formattedMemory)"
        case .failed(let msg): msg
        case .unloadedByPressure: "Released due to system memory pressure"
        }
    }

    @ViewBuilder
    private var modelActionButton: some View {
        switch modelStatus {
        case .ready:
            Button("Unload") {
                Task {
                    await LocalModelService.shared.unload()
                    await refreshModelState()
                }
            }
            .controlSize(.small)
        case .idle, .unloadedByPressure, .failed:
            Button("Load") {
                Task {
                    await LocalModelService.shared.warmUp()
                    await refreshModelState()
                }
            }
            .controlSize(.small)
        case .loading, .downloading:
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        dashboardSection("Memory") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MLX Buffer Usage")
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    Text(formattedMemory)
                        .font(.system(size: SageDesign.Typography.captionSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                pressureBadge
            }
            .animation(SageDesign.Motion.contentCrossFade, value: memoryBytes)
            .padding(SageDesign.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(SageDesign.Chrome.strokeOpacity),
                        lineWidth: AccessibilityPreferences.increaseContrast ? 1 : 0.5
                    )
            }
        }
    }

    private var pressureBadge: some View {
        let (text, color): (String, Color) = switch pressureLevel {
        case .normal: ("Normal", .green)
        case .warning: ("Warning", .orange)
        case .critical: ("Critical", .red)
        }
        return Text(text)
            .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .animation(.easeInOut(duration: 0.3), value: pressureLevelKey)
    }

    private var pressureLevelKey: Int {
        switch pressureLevel {
        case .normal: 0
        case .warning: 1
        case .critical: 2
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
            .padding(SageDesign.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(SageDesign.Chrome.strokeOpacity),
                        lineWidth: AccessibilityPreferences.increaseContrast ? 1 : 0.5
                    )
            }
        }
    }

    private var tokenSummary: String {
        let usage = appState.agent.tokenUsage
        return "In: \(formatTokenCount(usage.input)) • Out: \(formatTokenCount(usage.output))"
    }

    // MARK: - MCP Servers

    private var mcpServersSection: some View {
        dashboardSection("MCP Servers") {
            let servers = appState.capabilities.mcpServers
            if servers.isEmpty {
                Text("No servers configured")
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .foregroundStyle(.tertiary)
                    .padding(SageDesign.Spacing.md)
            } else {
                VStack(spacing: SageDesign.Spacing.sm) {
                    ForEach(servers, id: \.id) { server in
                        MCPServerRow(server: server) {
                            appState.capabilities.retryServer(server.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var formattedMemory: String {
        formatBytes(memoryBytes)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        let k = Double(count) / 1000
        return String(format: "%.1fk", k)
    }

    private func refreshModelState() async {
        let newStatus = await LocalModelService.shared.status
        let newBytes = await LocalModelService.shared.memoryFootprintBytes
        let newPressure = MemoryPressureMonitor.shared.currentLevel
        withAnimation(SageDesign.Motion.contentCrossFade) {
            modelStatus = newStatus
            memoryBytes = newBytes
            pressureLevel = newPressure
        }
    }

    private func startPolling() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in await refreshModelState() }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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

                Text(server.name)
                    .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if server.status == .error || server.status == .reconnecting {
                    Button("Retry") { onRetry() }
                        .controlSize(.small)
                }

                if !server.recentLogs.isEmpty {
                    Button {
                        withAnimation(SageDesign.Motion.contentCrossFade) {
                            logsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(logsExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: logsExpanded)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
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
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(SageDesign.Chrome.strokeOpacity),
                    lineWidth: AccessibilityPreferences.increaseContrast ? 1 : 0.5
                )
        }
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
}
