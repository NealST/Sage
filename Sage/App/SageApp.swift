//
//  SageApp.swift
//  Sage
//
//  Menu-bar-first app: the MenuBarExtra is the primary scene. The command
//  bar only appears while the app is regular (an agent window is open), so
//  commands mirror the menu-bar actions instead of introducing new ones —
//  one vocabulary, discoverable from two places.
//

import SwiftUI

@main
struct SageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    private var appState: AppState { appDelegate.appState }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                onOpenAgent: {
                    appDelegate.showAgentWindow()
                },
                onOpenProject: {
                    appDelegate.openProjectPanel()
                },
                onCreateProject: {
                    appDelegate.createProjectPanel()
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
        } label: {
            MenuBarStatusIcon()
                .environment(appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Project…") {
                    appDelegate.openProjectPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("New Project…") {
                    appDelegate.createProjectPanel()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                // ⌘W is otherwise missing: every Sage window is an AppKit
                // NSWindow outside SwiftUI scenes, so no default Close item
                // is generated. performClose routes through
                // windowShouldClose (hide vs dispose).
                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Task") {
                Button("Start Fresh") {
                    appState.startFreshInKeySession()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!appState.agent.canStartFresh)

                Button("Browse Tasks…") {
                    appState.browseTasksInKeySession()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!appState.hasBrowsableTaskHistory)

                Button("Export Task as Markdown…") {
                    appState.exportKeySessionTask()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!appState.keySessionHasTranscript)

                Button("Find in Task…") {
                    appState.findInKeySessionTask()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(!appState.keySessionHasTranscript)
            }

            CommandGroup(after: .toolbar) {
                Button("Show Task") {
                    appState.selectWorkspaceTab(.task)
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!appState.keySessionIsProject)

                Button("Show Files") {
                    appState.selectWorkspaceTab(.files)
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!appState.keySessionIsProject)

                Button("Show History") {
                    appState.selectWorkspaceTab(.history)
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(!appState.keySessionIsProject)
            }

            CommandGroup(after: .windowList) {
                Button("Open Sage") {
                    appDelegate.showAgentWindow()
                }

                Button("Dashboard") {
                    appDelegate.showDashboard()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Settings…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
