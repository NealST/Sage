//
//  MCPManageView.swift
//  Sage
//

import SwiftUI

struct MCPManageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sageTypography) private var type
    @State private var draftName = ""
    @State private var draftCommand = ""
    @State private var draftArgs = ""
    @State private var showingAdd = false
    @State private var serverPendingDelete: MCPServerConfig?
    @State private var toolsByServerID: [String: [MCPToolInfo]] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            if appState.mcpHub.mcpServers.isEmpty {
                ContentUnavailableView {
                    Label("No MCP Servers", systemImage: "cable.connector")
                } description: {
                    Text("Add a stdio MCP server to expose its tools to Sage.")
                } actions: {
                    Button("Add Server") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.mcpHub.mcpServers) { server in
                        serverRow(server)
                    }
                }
                .listStyle(.inset)
            }

            Divider().opacity(SageDesign.Chrome.dividerOpacity)
            footer
        }
        .frame(width: 560, height: 500)
        .onAppear { refreshToolsIndex() }
        .onChange(of: appState.mcpHub.mcpTools) { _, _ in
            refreshToolsIndex()
        }
        .sheet(isPresented: $showingAdd) {
            addSheet
        }
        .confirmationDialog(
            "Delete “\(serverPendingDelete?.name ?? "server")”?",
            isPresented: Binding(
                get: { serverPendingDelete != nil },
                set: { if !$0 { serverPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = serverPendingDelete?.id {
                    appState.mcpHub.deleteMCPServer(id)
                }
                serverPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                serverPendingDelete = nil
            }
        } message: {
            Text("This removes the server configuration and its tools from Sage.")
        }
    }

    private var header: some View {
        HStack {
            Text("MCP Servers")
                .font(.headline)
            Spacer()
            Button("Add Server") { showingAdd = true }
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text("stdio MCP servers run with Sage’s full user privileges and are not limited by the project sandbox.")
                .font(.system(size: type.micro))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    @ViewBuilder
    private func serverRow(_ server: MCPServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusIcon(server.status)
                Text(server.name)
                    .font(.system(size: type.body, weight: .semibold))
                Spacer()
                Toggle(
                    "Enabled for \(server.name)",
                    isOn: Binding(
                        get: { server.enabled },
                        set: { appState.mcpHub.setMCPEnabled(server.id, enabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Enabled for \(server.name)")
            }

            Text(server.command + (server.args.isEmpty ? "" : " " + server.args.joined(separator: " ")))
                .font(.system(size: type.micro, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            serverRowActions(server)

            if let tools = toolsByServerID[server.id], !tools.isEmpty {
                DisclosureGroup("Tools (\(server.toolCount))") {
                    ForEach(tools) { tool in
                        Text(tool.name)
                            .font(.system(size: type.micro))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: type.micro, weight: .medium))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(server.name), \(statusLabel(server))")
    }

    @ViewBuilder
    private func serverRowActions(_ server: MCPServerConfig) -> some View {
        HStack {
            Text(statusLabel(server))
                .font(.system(size: type.micro))
                .foregroundStyle(.secondary)
            Spacer()
            if server.status == .error || server.status == .disconnected {
                Button("Connect") {
                    Task { await appState.mcpHub.connect(serverID: server.id) }
                }
                .controlSize(.small)
            }
            Button("Delete", role: .destructive) {
                serverPendingDelete = server
            }
            .controlSize(.small)
        }
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add MCP Server")
                .font(.headline)
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
            TextField("Command", text: $draftCommand)
                .textFieldStyle(.roundedBorder)
            TextField("Arguments (space-separated)", text: $draftArgs)
                .textFieldStyle(.roundedBorder)
            if hasDuplicateDraftName {
                Text("Server names must be unique.")
                    .font(.system(size: type.micro))
                    .foregroundStyle(.red)
            }
            Text("The command runs in Sage's process sandbox. Only add servers you trust.")
                .font(.system(size: type.micro))
                .foregroundStyle(.secondary)
            Text("Example: npx  ·  -y @modelcontextprotocol/server-filesystem /Users/you")
                .font(.system(size: type.micro))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { showingAdd = false }
                Button("Add") {
                    let args = draftArgs
                        .split(whereSeparator: \.isWhitespace)
                        .map(String.init)
                    let server = MCPServerConfig(
                        name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
                        command: draftCommand.trimmingCharacters(in: .whitespacesAndNewlines),
                        args: args,
                        enabled: true
                    )
                    guard !server.name.isEmpty, !server.command.isEmpty else { return }
                    guard appState.mcpHub.addMCPServer(server) else { return }
                    draftName = ""
                    draftCommand = ""
                    draftArgs = ""
                    showingAdd = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty
                    || draftCommand.trimmingCharacters(in: .whitespaces).isEmpty
                    || hasDuplicateDraftName)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var hasDuplicateDraftName: Bool {
        let normalized = draftName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.mcpHub.mcpServers.contains { server in
            server.name.lowercased() == normalized
        }
    }

    private func refreshToolsIndex() {
        toolsByServerID = Dictionary(grouping: appState.mcpHub.mcpTools, by: \.serverID)
    }

    private func statusIcon(_ status: MCPServerStatus) -> some View {
        Image(systemName: symbol(for: status))
            .font(.system(size: type.micro, weight: .semibold))
            .foregroundStyle(color(for: status))
            .frame(width: 14)
            .accessibilityLabel(accessibilityStatusName(status))
    }

    private func accessibilityStatusName(_ status: MCPServerStatus) -> String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .error: return "Error"
        case .disconnected: return "Disconnected"
        case .disabled: return "Disabled"
        }
    }

    private func symbol(for status: MCPServerStatus) -> String {
        switch status {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.circle.fill"
        case .disconnected: return "circle"
        case .disabled: return "pause.circle"
        }
    }

    private func color(for status: MCPServerStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        case .disabled: return .gray.opacity(0.7)
        }
    }

    private func statusLabel(_ server: MCPServerConfig) -> String {
        switch server.status {
        case .connected: return "Connected · \(server.toolCount) tools"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .error: return server.statusMessage ?? "Error"
        case .disconnected: return "Disconnected"
        case .disabled: return "Disabled"
        }
    }
}
