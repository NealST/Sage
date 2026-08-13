//
//  SageApp.swift
//  Sage
//

import SwiftUI

@main
struct SageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Sage", systemImage: SageDesign.Symbol.brand) {
            MenuBarView(
                onOpenAgent: {
                    appDelegate.showAgentWindow()
                },
                onOpenSettings: {
                    appDelegate.showSettings()
                },
                onOpenDashboard: {
                    appDelegate.showDashboard()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
            .environment(appDelegate.appState)
            .environment(AccessibilitySettings.shared)
        }
        .menuBarExtraStyle(.menu)
    }
}
