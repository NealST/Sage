//
//  AppearanceTools.swift
//  Sage
//

import AppKit
import Foundation

// MARK: - Appearance

nonisolated struct ToggleAppearanceTool: AgentTool {
    let definition = ToolDefinition(
        name: "toggle_appearance",
        description: """
            Toggle macOS between Light and Dark appearance mode, or set a specific mode. \
            Returns the new appearance mode after the change. \
            Uses AppleScript to change the system setting — may show a brief permission prompt on first use.
            """,
        parameters: .schemaObject(
            properties: [
                "mode": .stringProperty("Set to 'light', 'dark', or 'toggle' (default). 'toggle' switches to the opposite of current."),
            ],
            required: []
        )
    )

    private struct Args: Decodable {
        let mode: String?
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let requestedMode = (args.mode ?? "toggle").lowercased()

        guard ["light", "dark", "toggle"].contains(requestedMode) else {
            throw ToolError.invalidArguments(
                "Invalid mode '\(args.mode ?? "")'. Use 'light', 'dark', or 'toggle'."
            )
        }

        let script: String
        switch requestedMode {
        case "light":
            script = """
                tell application "System Events"
                    tell appearance preferences to set dark mode to false
                end tell
                """

        case "dark":
            script = """
                tell application "System Events"
                    tell appearance preferences to set dark mode to true
                end tell
                """
        default: // toggle
            script = """
                tell application "System Events"
                    tell appearance preferences to set dark mode to not dark mode
                end tell
                """
        }

        // NSAppleScript must execute on the main thread
        return try await MainActor.run {
            let appleScript = NSAppleScript(source: script)
            var errorInfo: NSDictionary?
            appleScript?.executeAndReturnError(&errorInfo)

            if let error = errorInfo {
                let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                throw ToolError.operationFailed(
                    "Failed to change appearance: \(msg). Grant Sage permission to control System Events if prompted."
                )
            }

            // Read back the current state to confirm
            let checkScript = NSAppleScript(source: """
                tell application "System Events"
                    return dark mode of appearance preferences
                end tell
                """)
            let result = checkScript?.executeAndReturnError(nil)
            let isDark = result?.booleanValue ?? false
            let newMode = isDark ? "dark" : "light"

            return "[OK] Appearance set to \(newMode)"
        }
    }
}
