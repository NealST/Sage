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
                            statusDot(server.status)
                            Text(server.name)
                                .font(.system(size: 13, weight: .semibold))
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
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        HStack {
                            Text(statusLabel(server))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if server.status == .error || server.status == .disconnected {
                                Button("Connect") {
                                    Task { await appState.capabilities.connect(serverID: server.id) }
                                }
                                .controlSize(.small)
                            }
                            Button("Delete", role: .destructive) {
                                appState.capabilities.deleteMCPServer(server.id)
                            }
                            .controlSize(.small)
                        }

                        if !mcpTools(for: server).isEmpty {
                            DisclosureGroup("Tools (\(server.toolCount))") {
                                ForEach(mcpTools(for: server)) { tool in
                                    Text(tool.name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Text("stdio MCP servers (command + args). Tools appear after a successful connect.")
                    .font(.system(size: 11))
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
                .font(.system(size: 11))
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

    private func statusDot(_ status: MCPServerStatus) -> some View {
        Circle()
            .fill(color(for: status))
            .frame(width: 8, height: 8)
    }

    private func color(for status: MCPServerStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        case .disabled: return .gray.opacity(0.5)
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
