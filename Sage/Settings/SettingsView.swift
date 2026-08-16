//
//  SettingsView.swift
//  Sage
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: ModelSettings
    var onDone: (() -> Void)?
    var onOpenSkills: ((AgentSession) -> Void)?

    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var showMCPManage = false
    @State private var showEraseConfirm = false
    @State private var eraseMessage: String?
    /// Skills catalog session captured when Settings appears / manage opens.
    @State private var pinnedSkillsSession: AgentSession?

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
        .textSelection(.enabled)
        .onAppear {
            pinnedSkillsSession = appState.keySession
        }
        .onDisappear {
            testTask?.cancel()
            pinnedSkillsSession = nil
        }
        .sheet(isPresented: $showMCPManage) {
            MCPManageView()
                .sageScaledTypography()
                .sageAccessibilityObservation()
                .environment(appState)
                .environment(AccessibilitySettings.shared)
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
                    title: "Plan model",
                    error: nil
                ) {
                    TextField("same as Model", text: $settings.planModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                }

                sectionDivider

                settingsField(
                    title: "Execute model",
                    error: nil
                ) {
                    TextField("same as Model", text: $settings.executeModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                }

                sectionDivider

                settingsField(
                    title: "Review model",
                    error: nil
                ) {
                    TextField("same as Model", text: $settings.reviewModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
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
            .sagePanelBackground(cornerRadius: 10)

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
                    detail: "\(enabledSkillCount) of \(skillsCatalog.skills.count) enabled",
                    isFirst: true,
                    action: {
                        let session = pinnedSkillsSession ?? appState.keySession
                        pinnedSkillsSession = session
                        if let onOpenSkills {
                            onOpenSkills(session)
                        }
                    }
                )

                ForEach(Array(skillsCatalog.skills.prefix(4).enumerated()), id: \.element.id) { _, skill in
                    sectionDivider
                    quickToggleRow(
                        title: skill.name,
                        isOn: Binding(
                            get: {
                                skillsCatalog.skills.first(where: { $0.name == skill.name })?.enabled
                                    ?? skill.enabled
                            },
                            set: { enabled in
                                let session = pinnedSkillsSession ?? appState.keySession
                                session.skillCatalog.setSkillEnabled(skill, enabled: enabled)
                                Task { await appState.syncSkillEnablement(from: session) }
                            }
                        )
                    )
                }

                sectionDivider

                capabilityRow(
                    symbol: SageDesign.Symbol.mcp,
                    title: "MCP Servers",
                    detail: "\(connectedMCPCount) connected",
                    isLast: appState.mcpHub.mcpServers.isEmpty,
                    action: { showMCPManage = true }
                )

                ForEach(Array(appState.mcpHub.mcpServers.prefix(3).enumerated()), id: \.element.id) { index, server in
                    sectionDivider
                    quickToggleRow(
                        title: server.name,
                        detail: mcpStatusDetail(server),
                        isLast: index == min(2, appState.mcpHub.mcpServers.count - 1),
                        isOn: Binding(
                            get: {
                                appState.mcpHub.mcpServers.first(where: { $0.id == server.id })?.enabled
                                    ?? server.enabled
                            },
                            set: { appState.mcpHub.setMCPEnabled(server.id, enabled: $0) }
                        )
                    )
                }
            }
            .sagePanelBackground(cornerRadius: 10)
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
                .disabled(appState.agent.state.isBusy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .sagePanelBackground(cornerRadius: 10)
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
        case .reconnecting: return "Reconnecting…"
        case .error: return server.statusMessage ?? "Error"
        case .disconnected: return server.enabled ? "Disconnected" : nil
        case .disabled: return nil
        }
    }

    private var eraseDialogTitle: String {
        if case .awaitingConfirmation = appState.agent.state.phase {
            return "Erase data and abandon pending plan?"
        }
        return "Erase all local Sage data?"
    }

    private var eraseDialogMessage: String {
        if case .awaitingConfirmation = appState.agent.state.phase {
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

    private var skillsCatalog: SkillCatalog {
        (pinnedSkillsSession ?? appState.keySession).skillCatalog
    }

    private var enabledSkillCount: Int {
        skillsCatalog.skills.count(where: \.enabled)
    }

    private var connectedMCPCount: Int {
        appState.mcpHub.mcpServers.count(where: { $0.status == .connected })
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
        .environment(AccessibilitySettings.shared)
        .sageScaledTypography()
}
