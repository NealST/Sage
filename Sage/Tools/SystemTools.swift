//
//  SystemTools.swift
//  Sage
//

import AppKit
import Foundation
import UserNotifications

struct GetClipboardTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_clipboard",
        description: "Read the current text content of the system clipboard.",
        parameters: .schemaObject(properties: [:])
    )

    func call(argumentsJSON: String) async throws -> String {
        try await MainActor.run {
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            return text.isEmpty ? "(clipboard empty)" : text
        }
    }
}

struct SetClipboardTool: AgentTool {
    let definition = ToolDefinition(
        name: "set_clipboard",
        description: "Replace the system clipboard with the given text.",
        parameters: .schemaObject(
            properties: [
                "text": .stringProperty("Text to put on the clipboard"),
            ],
            required: ["text"]
        )
    )

    private struct Args: Decodable { let text: String }

    func call(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data)
        else {
            throw ToolError.invalidArguments(argumentsJSON)
        }
        return await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(args.text, forType: .string)
            return "Clipboard updated (\(args.text.count) characters)"
        }
    }
}

struct OpenApplicationTool: AgentTool {
    let definition = ToolDefinition(
        name: "open_application",
        description: "Open a macOS application by name (e.g. Notes, Safari, Finder).",
        parameters: .schemaObject(
            properties: [
                "name": .stringProperty("Application name as shown in /Applications"),
            ],
            required: ["name"]
        )
    )

    private struct Args: Decodable { let name: String }

    func call(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data)
        else {
            throw ToolError.invalidArguments(argumentsJSON)
        }

        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "\(NSHomeDirectory())/Applications/\(name).app",
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let config = NSWorkspace.OpenConfiguration()
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                return "Opened \(path)"
            } catch {
                continue
            }
        }

        throw ToolError.operationFailed("Could not find app '\(name)' in Applications")
    }
}

struct OpenURLTool: AgentTool {
    let definition = ToolDefinition(
        name: "open_url",
        description: "Open a URL in the default browser or handler.",
        parameters: .schemaObject(
            properties: [
                "url": .stringProperty("URL to open, including scheme"),
            ],
            required: ["url"]
        )
    )

    private struct Args: Decodable { let url: String }

    func call(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data),
              let url = URL(string: args.url),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else {
            throw ToolError.invalidArguments("Expected http(s) or mailto URL")
        }
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        guard ok else { throw ToolError.operationFailed("Failed to open \(args.url)") }
        return "Opened \(args.url)"
    }
}

struct NotifyTool: AgentTool {
    let definition = ToolDefinition(
        name: "notify",
        description: "Show a macOS user notification with a title and body.",
        parameters: .schemaObject(
            properties: [
                "title": .stringProperty("Notification title"),
                "body": .stringProperty("Notification body"),
            ],
            required: ["title", "body"]
        )
    )

    private struct Args: Decodable {
        let title: String
        let body: String
    }

    func call(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data)
        else {
            throw ToolError.invalidArguments(argumentsJSON)
        }

        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw ToolError.operationFailed("Notification permission was denied")
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
        return "Notification delivered"
    }
}
