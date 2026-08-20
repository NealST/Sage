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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SageDesign.Spacing.xl) {
                        tokenUsageSection
                        mcpServersSection
                        schedulesSection
                    }
                    .padding(.horizontal, SageDesign.Spacing.xl)
                    .padding(.top, 20)
                    .padding(.bottom, SageDesign.Spacing.lg)
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
            VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
                Text("MCP tools are full-trust: they are not limited to the project sandbox.")
                    .font(.system(size: SageDesign.Typography.captionSize))
                    .foregroundStyle(.secondary)
                if servers.isEmpty {
                    Text("No servers configured")
                        .font(.system(size: SageDesign.Typography.captionSize))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, SageDesign.Spacing.sm)
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
            .padding(SageDesign.Spacing.md)
        }
    }

    // MARK: - Schedules

    private var schedulesSection: some View {
        dashboardSection("Schedules") {
            let records = appState.schedules.records
            VStack(spacing: SageDesign.Spacing.sm) {
                if let message = appState.schedules.lastError {
                    HStack(alignment: .top, spacing: SageDesign.Spacing.sm) {
                        Text(message)
                            .font(.system(size: SageDesign.Typography.captionSize))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Dismiss") {
                            appState.schedules.clearLastError()
                        }
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(SageDesign.Spacing.md)
                    .sagePanelBackground(cornerRadius: 10)
                }
                if records.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No schedules")
                            .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                        Text("In a chat window: /schedule for Sage, /schedule-script for a command.")
                            .font(.system(size: SageDesign.Typography.captionSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SageDesign.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sagePanelBackground(cornerRadius: 10)
                } else {
                    ForEach(records) { record in
                        ScheduleDashboardRow(
                            record: record,
                            isRunning: appState.schedules.runningIDs.contains(record.id),
                            isQueued: appState.schedules.queuedIDs.contains(record.id),
                            isFocused: appState.focusedScheduleID == record.id,
                            runLog: appState.focusedScheduleID == record.id
                                ? appState.focusedScheduleRunLog
                                : nil,
                            onSetEnabled: { enabled in
                                Task {
                                    await appState.schedules.setEnabled(record.id, enabled: enabled)
                                }
                            },
                            onReplan: {
                                Task { await appState.schedules.replan(record.id) }
                            },
                            onOpenLastRun: {
                                Task {
                                    if let taskID = record.lastRunTaskID {
                                        await appState.revealScheduledTask(
                                            projectID: record.projectID,
                                            taskID: taskID
                                        )
                                    } else {
                                        appState.activateForExternalPanels()
                                    }
                                }
                            },
                            onDelete: {
                                Task {
                                    if appState.focusedScheduleID == record.id {
                                        appState.clearFocusedSchedule()
                                    }
                                    await appState.schedules.delete(record.id)
                                }
                            },
                            onStop: {
                                appState.schedules.cancelRun(record.id)
                            }
                        )
                        .id(record.id)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTokenCount(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        let k = Double(count) / 1_000
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

private struct ScheduleDashboardRow: View {
    let record: ScheduleRecord
    let isRunning: Bool
    let isQueued: Bool
    let isFocused: Bool
    let runLog: String?
    let onSetEnabled: (Bool) -> Void
    let onReplan: () -> Void
    let onOpenLastRun: () -> Void
    let onDelete: () -> Void
    let onStop: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: SageDesign.Spacing.sm) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                        .lineLimit(1)
                        .accessibilityLabel(
                            "\(record.title), \(record.cadence.shortLabel), \(statusWord.lowercased())"
                        )
                    Text(subtitle)
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(isFocused ? 6 : 2)
                }

                Spacer(minLength: SageDesign.Spacing.sm)

                if isRunning {
                    Button("Stop") { onStop() }
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Stop this run. The schedule stays on.")
                        .accessibilityLabel("Stop schedule \(record.title)")
                }

                Toggle(isOn: isOnBinding) {
                    Text("Enabled")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(isPaused ? "Resume this schedule" : "Pause this schedule")
                .accessibilityLabel(
                    isPaused
                        ? "Resume schedule \(record.title)"
                        : "Pause schedule \(record.title)"
                )
                .accessibilityValue(isPaused ? "Paused" : "On")

                if record.lastRunTaskID != nil {
                    Button("Open") { onOpenLastRun() }
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            record.status == .awaitingConfirmation ? Color.accentColor : Color.secondary
                        )
                        .accessibilityLabel(
                            record.status == .awaitingConfirmation
                                ? "Confirm schedule \(record.title)"
                                : "Open last run of \(record.title)"
                        )
                }

                if record.kind == .agent,
                   record.status != .awaitingConfirmation,
                   record.frozenWorkPlanJSON != nil || record.status == .failed {
                    Button("Re-plan") { onReplan() }
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear the frozen recipe. The next run will plan from scratch.")
                        .accessibilityLabel("Re-plan schedule \(record.title)")
                }

                Button("Delete", role: .destructive) {
                    confirmDelete = true
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Delete schedule \(record.title)")
            }
        }
        .padding(SageDesign.Spacing.md)
        .sagePanelBackground(cornerRadius: 10)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .confirmationDialog(
            "Delete “\(record.title)”?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sage will stop running this timetable.")
        }
    }

    private var isPaused: Bool {
        !record.enabled || record.status == .paused
    }

    /// Reads the record so a failed Pause/Resume snaps the switch back.
    private var isOnBinding: Binding<Bool> {
        Binding(
            get: { !isPaused },
            set: { enabled in
                onSetEnabled(enabled)
            }
        )
    }

    private var statusColor: Color {
        if isRunning { return .orange }
        if isQueued { return .orange.opacity(0.7) }
        if isPaused { return Color.secondary }
        switch record.status {
        case .failed: return .red
        case .needsFirstRun, .draft: return .orange
        case .awaitingConfirmation: return Color.accentColor
        case .armed: return .green
        case .paused: return Color.secondary
        }
    }

    private var statusWord: String {
        if isRunning { return "Running" }
        if isQueued { return "Queued" }
        if isPaused { return "Paused" }
        switch record.status {
        case .needsFirstRun, .draft: return "Needs setup"
        case .awaitingConfirmation: return "Needs confirmation"
        case .failed: return "Failed"
        case .armed: return "On"
        case .paused: return "Paused"
        }
    }

    private var subtitle: String {
        let kind = record.kind == .agent ? "Sage" : "Script"
        let next = nextFireText
        let statusLine = "\(kind) · \(record.cadence.shortLabel) · \(statusWord) · \(next)"
        if isFocused, let runLog, !runLog.isEmpty {
            return "\(statusLine)\n\(runLog)"
        }
        if let last = record.lastStatus, !last.isEmpty {
            return "\(statusLine)\n\(last)"
        }
        return statusLine
    }

    private var nextFireText: String {
        guard let date = record.nextFireAt else { return "No next run" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
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
