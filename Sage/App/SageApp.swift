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
                onOpenHUD: {
                    appDelegate.showHUD()
                },
                onOpenSettings: {
                    appDelegate.showSettings()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
            .environment(appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
