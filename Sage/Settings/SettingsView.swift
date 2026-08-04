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
                VStack(alignment: .leading, spacing: SageDesign.Spacing.xl) {
                    connectionSection
                    capabilitiesSection
                    privacySection
                }
                .padding(.horizontal, SageDesign.Spacing.xl)
                .padding(.top, 20)
                .padding(.bottom, SageDesign.Spacing.lg)
            }
            .frame(maxHeight: 520)

            footer
                .padding(.horizontal, SageDesign.Spacing.xl)
                .padding(.bottom, 18)
        }
        .frame(width: 440)
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

    // MARK: - Connection

    private var connectionSection: some View {
        settingsSection("Connection") {
            VStack(spacing: 0) {
                settingsField(
                    title: "Base URL",
                    error: baseURLValidationError,
                    isFirst: true
                ) {
                    TextField("https://api.openai.com/v1", text: $settings.baseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                        .onChange(of: settings.baseURL) { _, _ in clearTestResult() }
                }

                sectionDivider

                settingsField(
                    title: "Model",
                    error: modelValidationError
                ) {
                    TextField("gpt-4.1-mini", text: $settings.model)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                        .onChange(of: settings.model) { _, _ in clearTestResult() }
                }

                sectionDivider

                settingsField(
                    title: "API Key",
                    error: apiKeyValidationError,
                    isLast: true
                ) {
                    SecureField("sk-…", text: $settings.apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                        .onChange(of: settings.apiKey) { _, _ in clearTestResult() }
                }
            }
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

            statusRow
        }
    }

    // MARK: - Capabilities

    private var capabilitiesSection: some View {
        settingsSection("Capabilities") {
            VStack(spacing: 0) {
                capabilityRow(
                    symbol: SageDesign.Symbol.skills,
                    title: "Skills",
                    detail: "\(enabledSkillCount) of \(appState.capabilities.skills.count) enabled",
                    isFirst: true,
                    action: { showSkillsManage = true }
                )

                ForEach(Array(appState.capabilities.skills.prefix(4).enumerated()), id: \.element.id) { _, skill in
                    sectionDivider
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

                sectionDivider

                capabilityRow(
                    symbol: SageDesign.Symbol.mcp,
                    title: "MCP Servers",
                    detail: "\(connectedMCPCount) connected",
                    isLast: appState.capabilities.mcpServers.isEmpty,
                    action: { showMCPManage = true }
                )

                ForEach(Array(appState.capabilities.mcpServers.prefix(3).enumerated()), id: \.element.id) { index, server in
                    sectionDivider
                    quickToggleRow(
                        title: server.name,
                        detail: mcpStatusDetail(server),
                        isLast: index == min(2, appState.capabilities.mcpServers.count - 1),
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

    // MARK: - Privacy

    private var privacySection: some View {
        settingsSection("Privacy") {
            HStack(spacing: SageDesign.Spacing.md) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local history")
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    Text(eraseMessage ?? "Task events stay on this Mac.")
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
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
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

    // MARK: - Shared Components

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.sm) {
            Text(title)
                .font(.system(size: SageDesign.Typography.captionSize, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            content()
        }
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.leading, 14)
    }

    private var statusRow: some View {
        Group {
            if let persistenceError = settings.apiKeyPersistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                switch testState {
                case .idle:
                    Text("Stored in Keychain · saves automatically")
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
        .padding(.leading, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private func settingsField<Content: View>(
        title: String,
        error: String?,
        isFirst: Bool = false,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: SageDesign.Typography.microSize, weight: .medium))
                    .foregroundStyle(.secondary)

                content()
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, 14)
            .padding(.top, isFirst ? 12 : 10)
            .padding(.bottom, isLast ? 12 : 10)

            if let error {
                Text(error)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        }
    }

    private func capabilityRow(
        symbol: String,
        title: String,
        detail: String,
        isFirst: Bool = false,
        isLast: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SageDesign.Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quickToggleRow(
        title: String,
        detail: String? = nil,
        isLast: Bool = false,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: SageDesign.Spacing.md) {
            Spacer()
                .frame(width: 20)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.md) {
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
        .padding(.top, SageDesign.Spacing.lg)
    }

    // MARK: - Helpers

    private func mcpStatusDetail(_ server: MCPServerConfig) -> String? {
        switch server.status {
        case .connected: return nil
        case .connecting: return "Connecting…"
        case .error: return server.statusMessage ?? "Error"
        case .disconnected: return server.enabled ? "Disconnected" : nil
        case .disabled: return nil
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
        case .idle: return "API key stored in Keychain. Changes save automatically."
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
