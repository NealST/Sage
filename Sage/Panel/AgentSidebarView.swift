//
//  AgentSidebarView.swift
//  Sage
//

import SwiftUI

struct AgentSidebarView: View {
    @Environment(AppState.self) private var appState
    @Binding var searchText: String
    @State private var showSkillsManage = false
    @State private var showMCPManage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SageDesign.Spacing.sm) {
                Image(systemName: SageDesign.Symbol.search)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))
                TextField("Search chats…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: SageDesign.Typography.captionSize))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, SageDesign.Spacing.md)
            .padding(.top, SageDesign.Spacing.md)

            Button {
                appState.agent.createSession()
            } label: {
                Label("New Chat", systemImage: SageDesign.Symbol.newChat)
                    .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SageDesign.Spacing.sm)
            .padding(.top, SageDesign.Spacing.sm)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !pinnedSessions.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(pinnedSessions) { session in
                            sessionRow(session)
                        }
                    }

                    sectionHeader("Chats")
                    ForEach(filteredSessions) { session in
                        sessionRow(session)
                    }

                    sectionHeaderWithAction("Skills") {
                        showSkillsManage = true
                    }
                    ForEach(appState.capabilities.skills) { skill in
                        skillRow(skill)
                    }
                    if appState.capabilities.skills.isEmpty {
                        emptyHint("No skills found")
                    }

                    sectionHeaderWithAction("MCP") {
                        showMCPManage = true
                    }
                    ForEach(appState.capabilities.mcpServers) { server in
                        mcpRow(server)
                    }
                    if appState.capabilities.mcpServers.isEmpty {
                        emptyHint("Add MCP servers in Manage")
                    }
                }
                .padding(.horizontal, SageDesign.Spacing.sm)
                .padding(.bottom, SageDesign.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .sheet(isPresented: $showSkillsManage) {
            SkillsManageView()
                .environment(appState)
        }
        .sheet(isPresented: $showMCPManage) {
            MCPManageView()
                .environment(appState)
        }
    }

    private var filteredSessions: [ChatSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.agent.sessions.filter { session in
            guard !session.isPinned else { return false }
            if query.isEmpty { return true }
            return session.title.localizedCaseInsensitiveContains(query)
                || session.preview.localizedCaseInsensitiveContains(query)
        }
    }

    private var pinnedSessions: [ChatSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.agent.sessions.filter { session in
            guard session.isPinned else { return false }
            if query.isEmpty { return true }
            return session.title.localizedCaseInsensitiveContains(query)
                || session.preview.localizedCaseInsensitiveContains(query)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, SageDesign.Spacing.md)
            .padding(.bottom, 4)
    }

    private func sectionHeaderWithAction(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Manage", action: action)
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, SageDesign.Spacing.md)
        .padding(.bottom, 4)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        let isActive = session.id == appState.agent.activeSessionID
        let hasPending = session.pendingPlan != nil
            || (isActive && {
                if case .awaitingConfirmation = appState.agent.phase { return true }
                return false
            }())

        return Button {
            appState.agent.selectSession(session.id)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: SageDesign.Typography.bodySize, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(session.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if hasPending {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Pending confirmation")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) {
                appState.agent.deleteSession(session.id)
            }
        }
    }

    private func skillRow(_ skill: SkillRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(skill.name)
                .font(.system(size: SageDesign.Typography.captionSize))
                .lineLimit(1)
            Spacer(minLength: 0)
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { skill.enabled },
                    set: { appState.capabilities.setSkillEnabled(skill.name, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skill.name), \(skill.enabled ? "enabled" : "disabled")")
    }

    private func mcpRow(_ server: MCPServerConfig) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(mcpColor(server.status))
                .frame(width: 7, height: 7)
            Text(server.name)
                .font(.system(size: SageDesign.Typography.captionSize))
                .lineLimit(1)
            Spacer(minLength: 0)
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { server.enabled },
                    set: { appState.capabilities.setMCPEnabled(server.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(server.name), \(server.status.rawValue)")
    }

    private func mcpColor(_ status: MCPServerStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .error: return .red
        case .disconnected: return .secondary
        case .disabled: return .gray.opacity(0.45)
        }
    }

    private var sidebarBackground: some View {
        Group {
            if AccessibilityPreferences.reduceTransparency {
                Color(nsColor: .controlBackgroundColor)
            } else {
                Color.primary.opacity(0.03)
            }
        }
    }
}
