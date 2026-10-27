//
//  SettingsView.swift
//  Sage
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: ModelSettings
    /// Registers a handler that applies deep-link presentation requests
    /// (e.g. the Dashboard's MCP empty state) whenever Settings is shown.
    var onPresentationRequest: (@escaping (SettingsPresentationRequest) -> Void) -> Void = { _ in }
    /// Keeps the NSWindow title in step with the visible pane (HIG: the
    /// settings window's title follows its pane).
    var onTitleChange: (String) -> Void = { _ in }

    @State private var selectedPane: SettingsPane = Self.restoredPane()
    @State private var showSkillsManage = false
    @State private var testState: SettingsConnectionTestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var showMCPManage = false
    /// `nil` = no erase attempted; the pane colors status from the outcome.
    @State private var eraseSucceeded: Bool?
    /// Skills catalog session captured when Settings appears / manage opens.
    @State private var pinnedSkillsSession: AgentSession?
    /// Owned here so the sheet's edit state survives parent re-renders and is
    /// clean at every presentation.
    @State private var skillsEditSession = SkillsEditSession()
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
        .frame(minWidth: SettingsWindowMetrics.minWidth, minHeight: SettingsWindowMetrics.minHeight)
        .onAppear {
            pinnedSkillsSession = appState.keySession
            refreshLoginItem()
            // The window outlives its panes — don't replay a previous visit's
            // erase outcome.
            eraseSucceeded = nil
            onPresentationRequest { applyPresentation($0) }
            onTitleChange(selectedPane.title)
        }
        .onChange(of: selectedPane) { _, pane in
            UserDefaults.standard.set(pane.rawValue, forKey: Self.paneStorageKey)
            onTitleChange(pane.title)
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
        .sheet(isPresented: $showSkillsManage) {
            SkillsManageView(
                pinnedSession: pinnedSkillsSession ?? appState.keySession,
                editSession: skillsEditSession
            )
                .frame(minWidth: 640, idealWidth: 760, minHeight: 440, idealHeight: 560)
                .sageScaledTypography()
                .sageAccessibilityObservation()
                .environment(appState)
                .environment(AccessibilitySettings.shared)
        }
        .onChange(of: showSkillsManage) { _, shown in
            if shown {
                skillsEditSession.reset()
            }
        }
    }

    /// HIG: restore the most recently viewed pane when Settings reopens.
    /// Internal so the window controller can seed the NSWindow title.
    static let paneStorageKey = "sage.settings.selectedPane"

    private static func restoredPane() -> SettingsPane {
        guard let raw = UserDefaults.standard.string(forKey: paneStorageKey),
              let pane = SettingsPane(rawValue: raw)
        else { return .connection }
        return pane
    }

    /// Applies a deep-link request: select the pane, then raise the sheet.
    private func applyPresentation(_ request: SettingsPresentationRequest) {
        if let pane = request.pane {
            selectedPane = pane
        }
        if request.openMCPManage {
            // Selecting the pane first keeps the sheet's context legible.
            selectedPane = .capabilities
            showMCPManage = true
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .connection:
            SettingsConnectionSection(
                settings: settings,
                onFieldChange: clearTestResult
            )
            Section {
                Button {
                    if testState == .testing {
                        cancelConnectionTest()
                    } else {
                        runConnectionTest()
                    }
                } label: {
                    if testState == .testing {
                        // The probe has no side effects, so HIG prescribes a
                        // Cancel affordance instead of a dead button.
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Cancel")
                        }
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(!canTest && testState != .testing)
                .help(
                    canTest
                        ? "Send a request to verify the connection"
                        : "Enter Base URL and API key first"
                )
            } footer: {
                ConnectionStatusRow(settings: settings, testState: testState)
            }

        case .models:
            SettingsModelsSection(settings: settings)

        case .capabilities:
            SettingsCapabilitiesSection(
                pinnedSkillsSession: $pinnedSkillsSession,
                showMCPManage: $showMCPManage,
                showSkillsManage: $showSkillsManage
            )

        case .startup:
            SettingsAppearanceSection()
            SettingsSchedulesSection(
                openAtLogin: $openAtLogin,
                loginItemHint: loginItemHint,
                onToggle: setOpenAtLogin
            )
            SettingsHotkeySection()

        case .privacy:
            SettingsPrivacySection(
                eraseSucceeded: eraseSucceeded,
                isBusy: appState.agent.state.isBusy
            ) {
                Task {
                    let didErase = await appState.eraseAllLocalData()
                    eraseSucceeded = didErase
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

    private func cancelConnectionTest() {
        testTask?.cancel()
        testTask = nil
        testState = .idle
    }

    private func runConnectionTest() {
        guard canTest else { return }
        testTask?.cancel()
        testState = .testing
        let snapshot = ModelSettingsSnapshot(
            baseURL: settings.baseURL,
            model: settings.defaultSelection.origin == .cloud
                ? settings.defaultSelection.identifier
                : "gpt-4.1-mini",
            apiKey: settings.apiKey,
            origin: .cloud
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
