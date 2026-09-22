//
//  DashboardView+Schedules.swift
//  Sage
//

import SwiftUI
import AppKit
import UserNotifications

extension DashboardView {
    // MARK: - Schedules

    /// Running / queued first, then rows needing attention (failed, waiting on
    /// review), then by next fire time — the actionable ones land above the
    /// fold without scrolling. Attention rows rank above healthy ones even
    /// though they have no next fire time.
    var sortedScheduleRecords: [ScheduleRecord] {
        appState.schedules.records.sorted { lhs, rhs in
            let lhsActive = appState.schedules.runningIDs.contains(lhs.id)
                || appState.schedules.queuedIDs.contains(lhs.id)
            let rhsActive = appState.schedules.runningIDs.contains(rhs.id)
                || appState.schedules.queuedIDs.contains(rhs.id)
            if lhsActive != rhsActive { return lhsActive }
            let lhsAttention = lhs.status == .failed || lhs.status == .awaitingConfirmation
            let rhsAttention = rhs.status == .failed || rhs.status == .awaitingConfirmation
            if lhsAttention != rhsAttention { return lhsAttention }
            return (lhs.nextFireAt ?? .distantFuture) < (rhs.nextFireAt ?? .distantFuture)
        }
    }

    var schedulesSection: some View {
        dashboardSection("Schedules") {
            let records = sortedScheduleRecords
            let lastError = appState.schedules.lastError
            GlassEffectContainer(spacing: SageDesign.Glass.containerSpacing) {
                VStack(spacing: SageDesign.Spacing.small) {
                    if notificationsDenied, !records.isEmpty {
                        HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
                            Image(systemName: "bell.slash")
                                .sageFont(type.caption)
                                .foregroundStyle(SageDesign.Palette.warning)
                                .accessibilityHidden(true)
                            Text("Notifications are off. Sage can’t alert you when a schedule finishes or fails.")
                                .sageFont(type.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                if let url = URL(
                                    string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text("System Settings…")
                                    .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
                                    .padding(.vertical, SageDesign.Spacing.compactChipVertical)
                                    .contentShape(Rectangle())
                            }
                            .controlSize(.small)
                            .buttonStyle(SagePlainActionButtonStyle())
                            .foregroundStyle(Color.accentColor)
                            .help("Open the Notifications pane in System Settings")
                        }
                        .padding(SageDesign.Spacing.medium)
                        .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
                    }
                    if let message = lastError {
                        HStack(alignment: .top, spacing: SageDesign.Spacing.small) {
                            Text(message)
                                .sageFont(type.caption)
                                .foregroundStyle(SageDesign.Palette.dangerText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                Task { await appState.schedules.reload() }
                            } label: {
                                Text("Retry")
                                    .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
                                    .padding(.vertical, SageDesign.Spacing.compactChipVertical)
                                    .contentShape(Rectangle())
                            }
                            .controlSize(.small)
                            .buttonStyle(SagePlainActionButtonStyle())
                            .foregroundStyle(Color.accentColor)
                            Button {
                                appState.schedules.clearLastError()
                            } label: {
                                Text("Dismiss")
                                    .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
                                    .padding(.vertical, SageDesign.Spacing.compactChipVertical)
                                    .contentShape(Rectangle())
                            }
                            .controlSize(.small)
                            .buttonStyle(SagePlainActionButtonStyle())
                            .foregroundStyle(.secondary)
                        }
                        .padding(SageDesign.Spacing.medium)
                        .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
                    }
                    // A load failure is not an empty list — and before the
                    // first load lands, show nothing rather than flash the
                    // empty state at schedules that are on their way in.
                    if records.isEmpty, lastError == nil, appState.schedules.isLoaded {
                        VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
                            Text("No schedules")
                                .sageFont(type.body, weight: .medium)
                            Text("In a chat window: /schedule for Sage, /schedule-script for a command.")
                                .sageFont(type.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(SageDesign.Spacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
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
                                onRunNow: {
                                    appState.schedules.enqueue(record.id, isTrial: true)
                                },
                                onOpenLastRun: {
                                    Task {
                                        if let taskID = record.lastRunTaskID {
                                            await appState.revealTask(
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
    }

    // MARK: - Helpers

    func formatTokenCount(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        let thousands = Double(count) / 1_000
        return String(format: "%.1fk", thousands)
    }

    // MARK: - Section Builder

    func dashboardSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text(title)
                .sageFont(type.caption, weight: .semibold)
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
    let onRunNow: () -> Void
    let onOpenLastRun: () -> Void
    let onDelete: () -> Void
    let onStop: () -> Void

    @Environment(\.sageTypography) private var type
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
            HStack(spacing: SageDesign.Spacing.small) {
                Circle()
                    .fill(statusColor)
                    .frame(width: SageDesign.Control.statusDotDiameter, height: SageDesign.Control.statusDotDiameter)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
                    Text(record.title)
                        .sageFont(type.body, weight: .medium)
                        .lineLimit(1)
                        .accessibilityLabel(
                            "\(record.title), \(record.cadence.shortLabel), \(statusWord.lowercased())"
                        )
                    Text(subtitle)
                        .sageMicro(type.micro)
                        .foregroundStyle(.secondary)
                        .lineLimit(isFocused ? 6 : 2)
                }

                Spacer(minLength: SageDesign.Spacing.small)

                Text(nextFireText)
                    .sageFont(type.caption)
                    .foregroundStyle(nextFireColor)
                    .lineLimit(1)
                    .help(nextFireHelp)

                if isRunning {
                    Button {
                        onStop()
                    } label: {
                        Text("Stop")
                            .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
                            .padding(.vertical, SageDesign.Spacing.compactChipVertical)
                            .contentShape(Rectangle())
                    }
                    .controlSize(.small)
                    .buttonStyle(SagePlainActionButtonStyle())
                    .foregroundStyle(.secondary)
                    .help("Stop this run. The schedule stays on.")
                    .accessibilityLabel("Stop schedule \(record.title)")
                }

                Toggle(isOn: isOnBinding) {
                    Text("Enabled")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(isPaused ? "Resume this schedule" : "Pause this schedule")
                .accessibilityLabel(
                    isPaused
                        ? "Resume schedule \(record.title)"
                        : "Pause schedule \(record.title)"
                )
                .accessibilityValue(isPaused ? "Paused" : "On")

                if record.lastRunTaskID != nil {
                    Button {
                        onOpenLastRun()
                    } label: {
                        Text("Open")
                            .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
                            .padding(.vertical, SageDesign.Spacing.compactChipVertical)
                            .contentShape(Rectangle())
                    }
                    .controlSize(.small)
                    .buttonStyle(SagePlainActionButtonStyle())
                    .foregroundStyle(
                        record.status == .awaitingConfirmation
                            ? SageDesign.Palette.warningText
                            : Color.secondary
                    )
                    .help(
                        record.status == .awaitingConfirmation
                            ? "Open the run that needs your review"
                            : "Open the last run of this schedule"
                    )
                    .accessibilityLabel(
                        record.status == .awaitingConfirmation
                            ? "Review schedule \(record.title)"
                            : "Open last run of \(record.title)"
                    )
                }

                // Transient and infrequent actions fold into one menu so the
                // resting row carries Open, the toggle, and this — a trailing
                // cluster reads as a toolbar past four controls.
                Menu {
                    if canRunNow {
                        Button("Run Now") { onRunNow() }
                    }
                    if canReplan {
                        Button("Re-plan") { onReplan() }
                    }
                    Button("Delete…", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .sageFont(type.caption)
                        .frame(width: SageDesign.Control.iconButtonLarge, height: SageDesign.Control.iconButtonLarge)
                        .sageHitSlop(visualSize: SageDesign.Control.iconButtonLarge)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .buttonStyle(.plain)
                .help("More actions for this schedule")
                .accessibilityLabel("More actions for schedule \(record.title)")
            }
        }
        .padding(SageDesign.Spacing.medium)
        .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
        .overlay {
            RoundedRectangle(cornerRadius: SageDesign.Glass.card)
                .strokeBorder(
                    Color.accentColor.opacity(SageDesign.Chrome.accentRingOpacity),
                    lineWidth: 1
                )
                .opacity(isFocused ? 1 : 0)
        }
        .animation(SageDesign.Motion.expandAnimation, value: isFocused)
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

    var isPaused: Bool {
        !record.enabled || record.status == .paused
    }

    /// Reads the record so a failed Pause/Resume snaps the switch back.
    var isOnBinding: Binding<Bool> {
        Binding(
            get: { !isPaused },
            set: { enabled in
                onSetEnabled(enabled)
            }
        )
    }

    var statusColor: Color {
        if isRunning { return SageDesign.Palette.warning }
        if isQueued { return SageDesign.Palette.warning.opacity(SageDesign.Chrome.deemphasizedContentOpacity) }
        if isPaused { return Color.secondary }
        switch record.status {
        case .failed: return SageDesign.Palette.danger
        case .needsFirstRun, .draft: return SageDesign.Palette.warning
        case .awaitingConfirmation: return SageDesign.Palette.warning
        case .armed: return SageDesign.Palette.success
        case .paused: return Color.secondary
        }
    }

    var statusWord: String {
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

    /// The status word no longer lives in the subtitle (the dot and
    /// next-fire text already say it); VoiceOver still gets it via the
    /// title's accessibility label.
    var subtitle: String {
        let kind = record.kind == .agent ? "Sage" : "Script"
        let statusLine = "\(kind) · \(record.cadence.shortLabel)"
        if isFocused, let runLog, !runLog.isEmpty {
            return "\(statusLine)\n\(runLog)"
        }
        if let last = record.lastStatus, !last.isEmpty {
            return "\(statusLine)\n\(last)"
        }
        return statusLine
    }

    var nextFireText: String {
        if isRunning { return "Running" }
        if isQueued { return "Queued" }
        if record.status == .awaitingConfirmation { return "Waiting on your review" }
        if record.status == .failed { return "Needs attention" }
        if record.status == .needsFirstRun || record.status == .draft { return "Needs setup" }
        if isPaused { return "No next run" }
        guard let date = record.nextFireAt else { return "No next run" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var nextFireColor: Color {
        switch record.status {
        case .failed: return SageDesign.Palette.dangerText
        case .awaitingConfirmation, .needsFirstRun, .draft: return SageDesign.Palette.warningText
        default: return .secondary
        }
    }

    var nextFireHelp: String {
        guard let date = record.nextFireAt, record.status == .armed, !isPaused else {
            return nextFireText
        }
        return "Next run \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Enabled schedules that aren't mid-flight or parked on a decision can be trialed.
    var canRunNow: Bool {
        record.enabled
            && !isRunning
            && !isQueued
            && record.status != .awaitingConfirmation
    }

    /// Re-planning only makes sense for agent schedules with a frozen recipe
    /// or a failed one worth clearing.
    var canReplan: Bool {
        record.kind == .agent
            && record.status != .awaitingConfirmation
            && (record.frozenWorkPlanJSON != nil || record.status == .failed)
    }
}

// MARK: - MCP Server Row

struct MCPServerRow: View {
    let server: MCPServerConfig
    let onRetry: () -> Void
    @Environment(\.sageTypography) private var type
    @State private var logsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: SageDesign.Spacing.small) {
                Circle()
                    .fill(serverStatusColor)
                    .frame(width: SageDesign.Control.statusDotDiameter, height: SageDesign.Control.statusDotDiameter)
                    .accessibilityHidden(true)

                Text(server.name)
                    .sageFont(type.body, weight: .medium)
                    .lineLimit(1)
                    .accessibilityLabel("\(server.name), \(serverStatusAccessibilityName)")

                Spacer()

                if server.status == .error || server.status == .reconnecting {
                    Button {
                        onRetry()
                    } label: {
                        Text("Connect")
                            .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
                            .padding(.vertical, SageDesign.Spacing.compactChipVertical)
                            .contentShape(Rectangle())
                    }
                    .controlSize(.small)
                    .buttonStyle(SagePlainActionButtonStyle())
                    .foregroundStyle(Color.accentColor)
                    .help("Restart the connection to this server")
                    .accessibilityLabel("Connect server \(server.name)")
                }

                if !server.recentLogs.isEmpty {
                    Button(logsExpanded ? "Hide logs" : "Show logs", systemImage: "chevron.right") {
                        withAnimation(SageDesign.Motion.expandAnimation) {
                            logsExpanded.toggle()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(SagePlainActionButtonStyle())
                    .foregroundStyle(.secondary)
                    .sageMicro(type.micro, weight: .semibold)
                    .rotationEffect(.degrees(logsExpanded ? 90 : 0))
                    .help(logsExpanded ? "Hide recent logs" : "Show recent logs")
                    .accessibilityLabel(
                        logsExpanded
                            ? "Hide recent logs for \(server.name)"
                            : "Show recent logs for \(server.name)"
                    )
                }
            }

            // Status subtitle
            if let message = server.statusMessage {
                Text(message)
                    .sageMicro(type.micro)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SageDesign.Control.statusDotDiameter + SageDesign.Spacing.small) // align with name
                    .padding(.top, 2)
                    .contentTransition(.opacity)
            }

            // Expandable logs
            if logsExpanded && !server.recentLogs.isEmpty {
                ScrollView(.vertical) {
                    Text(server.recentLogs.joined(separator: "\n"))
                        .sageMicro(type.micro, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(.top, SageDesign.Spacing.small)
                .transition(SageDesign.Glass.appearTransition)
            }
        }
        .padding(SageDesign.Spacing.medium)
        .sagePanelBackground(cornerRadius: SageDesign.Glass.card)
        .animation(SageDesign.Motion.contentCrossFade, value: server.status)
    }

    var serverStatusColor: Color {
        switch server.status {
        case .connected: SageDesign.Palette.success
        case .connecting, .reconnecting: SageDesign.Palette.warning
        case .error: SageDesign.Palette.danger
        case .disabled, .disconnected: Color.secondary
        }
    }

    var serverStatusAccessibilityName: String {
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
