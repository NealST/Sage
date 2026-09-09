//
//  SettingsView.swift
//  Sage
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: ModelSettings
    var onOpenSkills: ((AgentSession) -> Void)?

    @State private var selectedPane: SettingsPane = .connection
    @State private var testState: SettingsConnectionTestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var showMCPManage = false
    @State private var eraseMessage: String?
    /// Skills catalog session captured when Settings appears / manage opens.
    @State private var pinnedSkillsSession: AgentSession?
    @State private var openAtLogin = SageLoginItem.isEnabled
    @State private var loginItemHint: String?

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.systemImage)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 200, max: 260)
        } detail: {
            Form {
                paneContent
            }
            .formStyle(.grouped)
            .sageScrollEdgeGlass()
            .navigationTitle(selectedPane.title)
            .textSelection(.enabled)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 680, minHeight: 480)
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
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .connection:
            SettingsConnectionSection(
                settings: settings,
                testState: testState,
                onFieldChange: clearTestResult
            )
            Section {
                Button("Test Connection") {
                    runConnectionTest()
                }
                .disabled(!canTest || testState == .testing)
            }

        case .capabilities:
            SettingsCapabilitiesSection(
                pinnedSkillsSession: $pinnedSkillsSession,
                showMCPManage: $showMCPManage,
                onOpenSkills: onOpenSkills
            )

        case .schedules:
            SettingsSchedulesSection(
                openAtLogin: $openAtLogin,
                loginItemHint: loginItemHint,
                onToggle: setOpenAtLogin
            )

        case .privacy:
            SettingsPrivacySection(
                eraseMessage: eraseMessage,
                isBusy: appState.agent.state.isBusy
            ) {
                Task {
                    let didErase = await appState.eraseAllLocalData()
                    eraseMessage = didErase
                        ? "Local history erased."
                        : "Could not erase local history."
                }
            }
        }
    }

    private var canTest: Bool {
        SettingsConnectionSection.canTest(settings)
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
        .environment(AppState())
        .environment(AccessibilitySettings.shared)
        .sageScaledTypography()
}
