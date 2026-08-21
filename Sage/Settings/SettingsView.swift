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

    @State private var testState: SettingsConnectionTestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var showMCPManage = false
    @State private var showEraseConfirm = false
    @State private var eraseMessage: String?
    /// Skills catalog session captured when Settings appears / manage opens.
    @State private var pinnedSkillsSession: AgentSession?
    @State private var openAtLogin = SageLoginItem.isEnabled
    @State private var loginItemHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SageDesign.Spacing.extraLarge) {
                    SettingsConnectionSection(
                        settings: settings,
                        testState: testState,
                        onFieldChange: clearTestResult
                    )
                    SettingsCapabilitiesSection(
                        pinnedSkillsSession: $pinnedSkillsSession,
                        showMCPManage: $showMCPManage,
                        onOpenSkills: onOpenSkills
                    )
                    SettingsSchedulesSection(
                        openAtLogin: $openAtLogin,
                        loginItemHint: loginItemHint,
                        onToggle: setOpenAtLogin
                    )
                    SettingsPrivacySection(
                        eraseMessage: eraseMessage,
                        isBusy: appState.agent.state.isBusy
                    ) {
                            eraseMessage = nil
                            showEraseConfirm = true
                    }
                }
                .padding(.horizontal, SageDesign.Spacing.extraLarge)
                .padding(.top, 20)
                .padding(.bottom, SageDesign.Spacing.large)
            }
            .frame(maxHeight: 520)

            footer
                .padding(.horizontal, SageDesign.Spacing.extraLarge)
                .padding(.bottom, 18)
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .textSelection(.enabled)
        .onAppear {
            pinnedSkillsSession = appState.keySession
            refreshLoginItem()
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
                    let didErase = await appState.eraseAllLocalData()
                    eraseMessage = didErase
                        ? "Local history erased."
                        : "Could not erase local history."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(eraseDialogMessage)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.medium) {
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
        .padding(.top, SageDesign.Spacing.large)
    }

    private var canTest: Bool {
        SettingsConnectionSection.canTest(settings)
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

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            try SageLoginItem.setEnabled(enabled)
            refreshLoginItem()
        } catch {
            refreshLoginItem()
            loginItemHint = error.localizedDescription
        }
    }

    private func refreshLoginItem() {
        openAtLogin = SageLoginItem.isEnabled
        if SageLoginItem.needsApproval {
            loginItemHint = "Allow Sage in System Settings → Login Items."
        } else {
            loginItemHint = nil
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
