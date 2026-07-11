//
//  AppDelegate.swift
//  Sage
//

import AppKit

extension Notification.Name {
    static let sageHUDHeightChanged = Notification.Name("sage.hudHeightChanged")
    static let sageOpenSettings = Notification.Name("sage.openSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hudController: HUDPanelController?
    private var settingsController: SettingsWindowController?
    private var hotkeyObserver: NSObjectProtocol?
    private var openSettingsObserver: NSObjectProtocol?

    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        hudController = HUDPanelController(appState: appState)
        settingsController = SettingsWindowController(settings: appState.settings)

        HotkeyManager.shared.start()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .sageToggleHUD,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hudController?.toggle()
            }
        }

        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .sageOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showSettings()
            }
        }

        Task {
            await appState.capabilities.bootstrap()
            await appState.agent.bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        if let hotkeyObserver {
            NotificationCenter.default.removeObserver(hotkeyObserver)
        }
        if let openSettingsObserver {
            NotificationCenter.default.removeObserver(openSettingsObserver)
        }
    }

    func toggleHUD() {
        hudController?.toggle()
    }

    func showHUD() {
        hudController?.show()
    }

    func showSettings() {
        settingsController?.show()
    }
}
