//
//  MCPManageView.swift
//  Sage
//

import SwiftUI

struct MCPManageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""
    @State private var draftCommand = ""
    @State private var draftArgs = ""
    @State private var showingAdd = false
    @State private var serverPendingDelete: MCPServerConfig?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MCP Servers")
                    .font(.headline)
                Spacer()
                Button("Add Server") { showingAdd = true }
            }
            .padding()

            Divider()

            List {
                ForEach(appState.capabilities.mcpServers) { server in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            statusIcon(server.status)
                            Text(server.name)
                                .font(.system(size: SageDesign.Typography.bodySize, weight: .semibold))
                            Spacer()
                            Toggle(
                                "Enabled",
                                isOn: Binding(
                                    get: { server.enabled },
                                    set: { appState.capabilities.setMCPEnabled(server.id, enabled: $0) }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        Text(server.command + (server.args.isEmpty ? "" : " " + server.args.joined(separator: " ")))
                            .font(.system(size: SageDesign.Typography.microSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack {
                            Text(statusLabel(server))
                                .font(.system(size: SageDesign.Typography.microSize))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if server.status == .error || server.status == .disconnected {
                                Button("Connect") {
                                    Task { await appState.capabilities.connect(serverID: server.id) }
                                }
                                .controlSize(.small)
                            }
                            Button("Delete", role: .destructive) {
                                serverPendingDelete = server
                            }
                            .controlSize(.small)
                        }

                        if !mcpTools(for: server).isEmpty {
                            DisclosureGroup("Tools (\(server.toolCount))") {
                                ForEach(mcpTools(for: server)) { tool in
                                    Text(tool.name)
                                        .font(.system(size: SageDesign.Typography.microSize))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Text("stdio MCP servers (command + args). Tools appear after a successful connect.")
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 500)
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
                    appState.capabilities.deleteMCPServer(id)
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
            Text("Example: npx  ·  -y @modelcontextprotocol/server-filesystem /Users/you")
                .font(.system(size: SageDesign.Typography.microSize))
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
                    appState.capabilities.addMCPServer(server)
                    draftName = ""
                    draftCommand = ""
                    draftArgs = ""
                    showingAdd = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty
                    || draftCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func mcpTools(for server: MCPServerConfig) -> [MCPToolInfo] {
        appState.capabilities.mcpTools.filter { $0.serverID == server.id }
    }

    private func statusIcon(_ status: MCPServerStatus) -> some View {
        Image(systemName: symbol(for: status))
            .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
            .foregroundStyle(color(for: status))
            .frame(width: 14)
            .accessibilityLabel(status.rawValue)
    }

    private func symbol(for status: MCPServerStatus) -> String {
        switch status {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.circle.fill"
        case .disconnected: return "circle"
        case .disabled: return "pause.circle"
        }
    }

    private func color(for status: MCPServerStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        case .disabled: return .gray.opacity(0.7)
        }
    }

    private func statusLabel(_ server: MCPServerConfig) -> String {
        switch server.status {
        case .connected: return "Connected · \(server.toolCount) tools"
        case .connecting: return "Connecting…"
        case .error: return server.statusMessage ?? "Error"
        case .disconnected: return "Disconnected"
        case .disabled: return "Disabled"
        }
    }
}
