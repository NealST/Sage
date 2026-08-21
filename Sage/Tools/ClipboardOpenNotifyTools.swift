//
//  ClipboardOpenNotifyTools.swift
//  Sage
//

import AppKit
import Foundation
import UserNotifications

nonisolated struct GetClipboardTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_clipboard",
        description: """
            Read the current text content of the system clipboard. \
            Returns \"(clipboard empty)\" if empty. Capped at 10K characters.
            """,
        parameters: .schemaObject(properties: [:])
    )

    private static let maxChars = 10_000

    func call(argumentsJSON: String) async throws -> String {
        await MainActor.run {
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            if text.isEmpty { return "(clipboard empty)" }
            if text.count > Self.maxChars {
                return String(text.prefix(Self.maxChars)) + "\n… (clipboard truncated at \(Self.maxChars) characters)"
            }
            return text
        }
    }
}

nonisolated struct SetClipboardTool: AgentTool {
    let definition = ToolDefinition(
        name: "set_clipboard",
        description: "Replace the entire system clipboard with the given text. Previous clipboard content is lost.",
        parameters: .schemaObject(
            properties: [
                "text": .stringProperty("Text to put on the clipboard"),
            ],
            required: ["text"]
        )
    )

    private struct Args: Decodable { let text: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(args.text, forType: .string)
        }
        return "[OK] Clipboard updated (\(args.text.count) characters)"
    }
}

nonisolated struct OpenApplicationTool: AgentTool {
    let definition = ToolDefinition(
        name: "open_application",
        description: """
            Open (or bring to front) a macOS application by its display name. \
            Examples: "Safari", "Notes", "Visual Studio Code", "Finder". \
            Searches /Applications, /System/Applications, ~/Applications, and Launch Services index. Case-insensitive.
            """,
        parameters: .schemaObject(
            properties: [
                "name": .stringProperty("Application display name (e.g. 'Safari', 'Visual Studio Code')"),
            ],
            required: ["name"]
        )
    )

    private struct Args: Decodable { let name: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strategy 1: Direct path lookup in common directories
        let candidates = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "\(NSHomeDirectory())/Applications/\(name).app",
            "/Applications/Setapp/\(name).app",
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let config = NSWorkspace.OpenConfiguration()
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            return "[OK] Opened \(path)"
        }

        // Strategy 2: Case-insensitive search in /Applications and /System/Applications
        if let match = findAppCaseInsensitive(name: name) {
            let config = NSWorkspace.OpenConfiguration()
            _ = try await NSWorkspace.shared.openApplication(at: match, configuration: config)
            return "[OK] Opened \(match.path)"
        }

        // Strategy 3: Fall back to `open -a` which uses Launch Services index
        // This handles apps in non-standard locations and partial name matches
        let (status, errMsg) = try await runOpenCommand(name: name)
        if status == 0 {
            return "[OK] Opened \(name) (via Launch Services)"
        }
        throw ToolError.operationFailed("Could not find app '\(name)'. \(errMsg)")
    }

    /// Runs `open -a <name>` without blocking the cooperative thread pool.
    private func runOpenCommand(name: String) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", name]
            let pipe = Pipe()
            process.standardError = pipe

            process.terminationHandler = { proc in
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: (proc.terminationStatus, errMsg))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    throwing: ToolError.operationFailed(
                        "Failed to launch open command: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    private func findAppCaseInsensitive(name: String) -> URL? {
        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        let lowered = name.lowercased()
        for dir in searchDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: []
            ) else { continue }
            if let match = items.first(where: { item in
                item.deletingPathExtension().lastPathComponent.lowercased() == lowered
            }) {
                return match
            }
        }
        return nil
    }
}

nonisolated struct OpenURLTool: AgentTool {
    let definition = ToolDefinition(
        name: "open_url",
        description: """
            Open a URL in the user's default browser (http/https) or mail client (mailto). \
            Other schemes are not allowed.
            """,
        parameters: .schemaObject(
            properties: [
                "url": .stringProperty(
                    "Full URL including scheme (e.g. 'https://example.com' or 'mailto:user@example.com')"
                ),
            ],
            required: ["url"]
        )
    )

    private struct Args: Decodable { let url: String }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        guard let url = URL(string: args.url),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else {
            throw ToolError.invalidArguments("Expected http(s) or mailto URL, got: \(args.url)")
        }
        let didOpen = await MainActor.run { NSWorkspace.shared.open(url) }
        guard didOpen else { throw ToolError.operationFailed("Failed to open \(args.url)") }
        return "[OK] Opened \(args.url)"
    }
}

nonisolated struct NotifyTool: AgentTool {
    let definition = ToolDefinition(
        name: "notify",
        description: """
            Show a macOS notification banner to the user. Use to signal task completion or important events. \
            Requires notification permission — will fail with a clear message if denied.
            """,
        parameters: .schemaObject(
            properties: [
                "title": .stringProperty("Short notification title (keep under 50 chars)"),
                "body": .stringProperty("Notification body text"),
            ],
            required: ["title", "body"]
        )
    )

    private struct Args: Decodable {
        let title: String
        let body: String
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        let center = UNUserNotificationCenter.current()

        // Check existing permission first to avoid redundant prompts
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                throw ToolError.operationFailed("Notification permission was denied")
            }

        case .denied:
            throw ToolError.operationFailed(
                "Notification permission denied. Enable in System Settings → Notifications → Sage."
            )

        case .authorized, .provisional, .ephemeral:
            break

        @unknown default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = args.title
        content.body = args.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try await center.add(request)
        return "[OK] Notification delivered"
    }
}
