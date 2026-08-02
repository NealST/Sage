//
//  SettingsView.swift
//  Sage
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: ModelSettings
    var onDone: (() -> Void)?

    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var showSkillsManage = false
    @State private var showMCPManage = false
    @State private var showEraseConfirm = false
    @State private var eraseMessage: String?

    private enum TestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    fields
                    statusRow
                    Divider()
                        .padding(.vertical, 16)
                    capabilities
                    Divider()
                        .padding(.vertical, 16)
                    privacy
                }
            }
            .frame(maxHeight: 520)

            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { testTask?.cancel() }
        .sheet(isPresented: $showSkillsManage) {
            SkillsManageView()
                .environment(appState)
        }
        .sheet(isPresented: $showMCPManage) {
            MCPManageView()
                .environment(appState)
        }
        .confirmationDialog(
            eraseDialogTitle,
            isPresented: $showEraseConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase Data", role: .destructive) {
                Task {
                    let ok = await appState.eraseAllLocalData()
                    eraseMessage = ok
                        ? "Local history erased."
                        : "Could not erase local history."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(eraseDialogMessage)
        }
    }

    private var eraseDialogTitle: String {
        if case .awaitingConfirmation = appState.agent.phase {
            return "Erase data and abandon pending plan?"
        }
        return "Erase all local Sage data?"
    }

    private var eraseDialogMessage: String {
        if case .awaitingConfirmation = appState.agent.phase {
            return "This deletes local task history and abandons the pending plan. Your API key in Keychain is kept."
        }
        return "This permanently deletes local task history from this Mac. Your API key in Keychain is kept."
    }

    private var fields: some View {
        VStack(spacing: 12) {
            settingsField(
                title: "Base URL",
                error: baseURLValidationError
            ) {
                TextField("https://api.openai.com/v1", text: $settings.baseURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .foregroundStyle(.primary)
                    .onChange(of: settings.baseURL) { _, _ in clearTestResult() }
            }

            settingsField(title: "Model", error: modelValidationError) {
                TextField("gpt-4.1-mini", text: $settings.model)
                    .textFieldStyle(.plain)
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .foregroundStyle(.primary)
                    .onChange(of: settings.model) { _, _ in clearTestResult() }
            }

            settingsField(title: "API Key", error: apiKeyValidationError) {
                SecureField("sk-…", text: $settings.apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .foregroundStyle(.primary)
                    .onChange(of: settings.apiKey) { _, _ in clearTestResult() }
            }
        }
    }

    private var statusRow: some View {
        Group {
            if let persistenceError = settings.apiKeyPersistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                switch testState {
                case .idle:
                    Text("API key is stored in Keychain. Changes save automatically.")
                        .foregroundStyle(.secondary)
                case .testing:
                    Label("Testing connection…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                case .success:
                    Label("Connection succeeded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
            }
        }
        .font(.system(size: SageDesign.Typography.microSize))
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPABILITIES")
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.secondary)

            capabilityRow(
                symbol: SageDesign.Symbol.skills,
                title: "Skills",
                detail: "\(enabledSkillCount) of \(appState.capabilities.skills.count) enabled",
                action: { showSkillsManage = true }
            )

            ForEach(appState.capabilities.skills.prefix(4)) { skill in
                quickToggleRow(
                    title: skill.name,
                    isOn: Binding(
                        get: {
                            appState.capabilities.skills.first(where: { $0.name == skill.name })?.enabled
                                ?? skill.enabled
                        },
                        set: { appState.capabilities.setSkillEnabled(skill.name, enabled: $0) }
                    )
                )
            }

            capabilityRow(
                symbol: SageDesign.Symbol.mcp,
                title: "MCP Servers",
                detail: "\(connectedMCPCount) connected",
                action: { showMCPManage = true }
            )

            ForEach(appState.capabilities.mcpServers.prefix(3)) { server in
                quickToggleRow(
                    title: server.name,
                    detail: mcpStatusDetail(server),
                    isOn: Binding(
                        get: {
                            appState.capabilities.mcpServers.first(where: { $0.id == server.id })?.enabled
                                ?? server.enabled
                        },
                        set: { appState.capabilities.setMCPEnabled(server.id, enabled: $0) }
                    )
                )
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIVACY")
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local history")
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    Text(eraseMessage ?? "Task events stay on this Mac in Sage’s database.")
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(
                            eraseMessage?.hasPrefix("Could") == true ? Color.orange : Color.secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Erase…") {
                    eraseMessage = nil
                    showEraseConfirm = true
                }
                .controlSize(.small)
                .disabled(appState.agent.isBusy)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
            }
        }
    }

    private func quickToggleRow(
        title: String,
        detail: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: SageDesign.Typography.bodySize))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 2)
    }

    private func mcpStatusDetail(_ server: MCPServerConfig) -> String? {
        switch server.status {
        case .connected: return nil
        case .connecting: return "Connecting…"
        case .error: return server.statusMessage ?? "Error"
        case .disconnected: return server.enabled ? "Disconnected" : nil
        case .disabled: return nil
        }
    }

    private func capabilityRow(
        symbol: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                Text(detail)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Manage…", action: action)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
        }
        .overlay {
            if AccessibilityPreferences.increaseContrast {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(SageDesign.Chrome.strokeOpacity),
                        lineWidth: 1
                    )
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Button("Test Connection") {
                runConnectionTest()
            }
            .disabled(!canTest || testState == .testing)
            .controlSize(.large)

            Spacer(minLength: 8)

            Button("Done") {
                onDone?()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 16)
    }

    private func settingsField<Content: View>(
        title: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: SageDesign.Typography.microSize, weight: .semibold))
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(SageDesign.Chrome.fillOpacity))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            error == nil
                                ? Color.primary.opacity(SageDesign.Chrome.strokeOpacity)
                                : Color.orange.opacity(0.7),
                            lineWidth: error == nil
                                ? (AccessibilityPreferences.increaseContrast ? 1 : 0.5)
                                : 1
                        )
                }
                .accessibilityLabel(title)

            if let error {
                Text(error)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var baseURLValidationError: String? {
        let trimmed = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Base URL is required" }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return "Enter a valid http(s) URL"
        }
        return nil
    }

    private var modelValidationError: String? {
        settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Model is required"
            : nil
    }

    private var apiKeyValidationError: String? {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API key is required"
        }
        return settings.apiKeyPersistenceError
    }

    private var canTest: Bool {
        baseURLValidationError == nil
            && modelValidationError == nil
            && apiKeyValidationError == nil
    }

    private var enabledSkillCount: Int {
        appState.capabilities.skills.count(where: \.enabled)
    }

    private var connectedMCPCount: Int {
        appState.capabilities.mcpServers.count(where: { $0.status == .connected })
    }

    private var statusAccessibilityLabel: String {
        if let persistenceError = settings.apiKeyPersistenceError {
            return persistenceError
        }
        switch testState {
        case .idle: return "API key is stored in Keychain. Changes save automatically."
        case .testing: return "Testing connection"
        case .success: return "Connection succeeded"
        case .failure(let message): return message
        }
    }

    private func clearTestResult() {
        if case .testing = testState { return }
        testState = .idle
    }

    private func runConnectionTest() {
        guard canTest else { return }
        testTask?.cancel()
        testState = .testing
        let snapshot = ModelSettingsSnapshot(
            baseURL: settings.baseURL,
            model: settings.model,
            apiKey: settings.apiKey
        )
        testTask = Task {
            do {
                try await ModelClient().probe(settings: snapshot)
                guard !Task.isCancelled else { return }
                testState = .success
            } catch {
                guard !Task.isCancelled else { return }
                testState = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    SettingsView(settings: .shared)
        .padding()
        .environment(AppState())
}
