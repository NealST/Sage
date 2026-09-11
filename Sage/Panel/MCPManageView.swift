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
    /// Failure text for the add sheet — cleared on reopen and on field edits.
    @State private var addError: String?
    @FocusState private var nameFieldFocused: Bool
    @State private var serverPendingDelete: MCPServerConfig?
    @State private var toolsByServerID: [String: [MCPToolInfo]] = [:]
    @State private var searchText = ""
    @ScaledMetric(relativeTo: .body) private var addSheetWidth: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            header

            if appState.mcpHub.mcpServers.isEmpty {
                ContentUnavailableView {
                    Label("No MCP Servers", systemImage: "cable.connector")
                } description: {
                    Text("Add a stdio MCP server to expose its tools to Sage.")
                } actions: {
                    Button("Add Server") { showingAdd = true }
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleServers) { server in
                        serverRow(server)
                    }

                    if isFiltering, visibleServers.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.inset)
                .sageScrollEdgeGlass()
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: "Search servers or tools"
                )
            }

            footer
        }
        // Ideal = previous fixed size; bounds let users grow the sheet when a
        // server exposes many tools.
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 500)
        .onAppear { refreshToolsIndex() }
        .onChange(of: appState.mcpHub.mcpTools) { _, _ in
            refreshToolsIndex()
        }
        .sheet(isPresented: $showingAdd) {
            addSheet
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var visibleServers: [MCPServerConfig] {
        guard isFiltering else { return appState.mcpHub.mcpServers }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return appState.mcpHub.mcpServers.filter { server in
            if server.name.localizedCaseInsensitiveContains(query) { return true }
            if server.command.localizedCaseInsensitiveContains(query) { return true }
            let toolNames = toolsByServerID[server.id] ?? []
            return toolNames.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private var header: some View {
        HStack {
            Text("MCP Servers")
                .sageFont(type.title, weight: .semibold)
            Spacer()
            Button("Add Server") { showingAdd = true }
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            Text("stdio MCP servers run with Sage’s full user privileges and are not limited by the project sandbox.")
                .sageMicro(type.micro)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
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
                    .sageFont(type.body, weight: .semibold)
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
                .sageMicro(type.micro, design: .monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            serverRowActions(server)

            if let tools = toolsByServerID[server.id], !tools.isEmpty {
                DisclosureGroup {
                    ForEach(tools) { tool in
                        Text(tool.name)
                            .sageMicro(type.micro)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Tools (\(server.toolCount))")
                        .monospacedDigit()
                }
                .sageMicro(type.micro, weight: .medium)
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
                .sageMicro(type.micro)
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
            .confirmationDialog(
                "Delete “\(server.name)”?",
                isPresented: Binding(
                    get: { serverPendingDelete?.id == server.id },
                    set: { if !$0 { serverPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    appState.mcpHub.deleteMCPServer(server.id)
                    serverPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    serverPendingDelete = nil
                }
            } message: {
                Text("This removes the server configuration and its tools from Sage.")
            }
        }
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.medium) {
            Text("Add MCP Server")
                .sageFont(type.title, weight: .semibold)

            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onChange(of: draftName) { _, _ in addError = nil }
                TextField("Command", text: $draftCommand)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draftCommand) { _, _ in addError = nil }
                TextField("Arguments (space-separated)", text: $draftArgs)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draftArgs) { _, _ in addError = nil }

                if hasDuplicateDraftName {
                    Text("Server names must be unique.")
                        .sageMicro(type.micro)
                        .foregroundStyle(SageDesign.Palette.danger)
                } else if commandHasWhitespace {
                    Text("Command can’t contain spaces — put the arguments in the Arguments field.")
                        .sageMicro(type.micro)
                        .foregroundStyle(SageDesign.Palette.danger)
                } else if let addError {
                    Text(addError)
                        .sageMicro(type.micro)
                        .foregroundStyle(SageDesign.Palette.danger)
                } else if missingRequiredFields {
                    Text("Enter a name and a command to add this server.")
                        .sageMicro(type.micro)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("The command runs with your full user privileges, outside the project sandbox. Only add servers you trust.")
                        .sageMicro(type.micro)
                        .foregroundStyle(.secondary)
                    Text("Example — Command: npx · Arguments: -y @modelcontextprotocol/server-filesystem /Users/you")
                        .sageMicro(type.micro)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { showingAdd = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    addServer()
                }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAddDraft)
            }
        }
        .padding(SageDesign.Spacing.large)
        .frame(width: addSheetWidth)
        .onAppear {
            addError = nil
            nameFieldFocused = true
        }
    }

    private var missingRequiredFields: Bool {
        draftName.trimmingCharacters(in: .whitespaces).isEmpty
            || draftCommand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The command is a single executable path — flags belong in Arguments.
    private var commandHasWhitespace: Bool {
        !draftCommand.isEmpty && draftCommand.contains(where: \.isWhitespace)
    }

    private var canAddDraft: Bool {
        !missingRequiredFields && !hasDuplicateDraftName && !commandHasWhitespace
    }

    private func addServer() {
        let server = MCPServerConfig(
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            command: draftCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            args: draftArgs.split(whereSeparator: \.isWhitespace).map(String.init),
            enabled: true
        )
        guard appState.mcpHub.addMCPServer(server) else {
            addError = "Couldn’t add this server — check the name and command, then try again."
            return
        }
        draftName = ""
        draftCommand = ""
        draftArgs = ""
        showingAdd = false
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
        Image(systemName: MCPServerStatusChrome.symbol(status))
            .sageMicro(type.micro, weight: .semibold)
            .foregroundStyle(MCPServerStatusChrome.color(status))
            .frame(width: 14)
            .accessibilityLabel(MCPServerStatusChrome.accessibilityName(status))
    }

    private func statusLabel(_ server: MCPServerConfig) -> String {
        MCPServerStatusChrome.label(server)
    }
}

private enum MCPServerStatusChrome {
    static func accessibilityName(_ status: MCPServerStatus) -> String {
        switch status {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .error: return "Error"
        case .disconnected: return "Disconnected"
        case .disabled: return "Disabled"
        }
    }

    static func symbol(_ status: MCPServerStatus) -> String {
        switch status {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.circle.fill"
        case .disconnected: return "circle"
        case .disabled: return "pause.circle"
        }
    }

    static func color(_ status: MCPServerStatus) -> Color {
        switch status {
        case .connected: return SageDesign.Palette.success
        case .connecting, .reconnecting: return SageDesign.Palette.warning
        case .error: return SageDesign.Palette.danger
        case .disconnected: return .secondary
        case .disabled: return Color.secondary.opacity(0.7)
        }
    }

    static func label(_ server: MCPServerConfig) -> String {
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
