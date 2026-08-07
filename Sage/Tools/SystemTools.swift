//
//  SystemTools.swift
//  Sage
//

import AppKit
import CoreAudio
import EventKit
import Foundation
import UserNotifications

struct GetClipboardTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_clipboard",
        description: "Read the current text content of the system clipboard. Returns \"(clipboard empty)\" if empty. Capped at 10K characters.",
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

struct SetClipboardTool: AgentTool {
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

struct OpenApplicationTool: AgentTool {
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
                continuation.resume(throwing: ToolError.operationFailed("Failed to launch open command: \(error.localizedDescription)"))
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
            if let match = items.first(where: {
                $0.deletingPathExtension().lastPathComponent.lowercased() == lowered
            }) {
                return match
            }
        }
        return nil
    }
}

struct OpenURLTool: AgentTool {
    let definition = ToolDefinition(
        name: "open_url",
        description: "Open a URL in the user's default browser (http/https) or mail client (mailto). Other schemes are not allowed.",
        parameters: .schemaObject(
            properties: [
                "url": .stringProperty("Full URL including scheme (e.g. 'https://example.com' or 'mailto:user@example.com')"),
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
        let ok = await MainActor.run { NSWorkspace.shared.open(url) }
        guard ok else { throw ToolError.operationFailed("Failed to open \(args.url)") }
        return "[OK] Opened \(args.url)"
    }
}

struct NotifyTool: AgentTool {
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

// MARK: - Volume Control

struct GetSystemVolumeTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_system_volume",
        description: """
            Get the current system output volume level (0–100) and mute state. \
            Returns format: "volume: 50\nmuted: false". \
            Uses CoreAudio default output device.
            """,
        parameters: .schemaObject(properties: [:])
    )

    func call(argumentsJSON: String) async throws -> String {
        let (volume, muted) = try getOutputVolume()
        let percent = Int(round(volume * 100))
        return "volume: \(percent)\nmuted: \(muted)"
    }
}

struct SetSystemVolumeTool: AgentTool {
    let definition = ToolDefinition(
        name: "set_system_volume",
        description: """
            Set the system output volume level. Value is 0–100 (clamped if out of range). \
            Optionally set mute state. Uses CoreAudio default output device. \
            Note: changing volume while muted does NOT automatically unmute — set mute=false explicitly.
            """,
        parameters: .schemaObject(
            properties: [
                "volume": .intProperty("Volume level 0–100"),
                "mute": .intProperty("Set to 1 to mute, 0 to unmute. Omit to leave mute state unchanged."),
            ],
            required: ["volume"]
        )
    )

    private struct Args: Decodable {
        let volume: Int
        let mute: Int?
    }

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let clamped = min(max(args.volume, 0), 100)
        let floatVolume = Float32(clamped) / 100.0

        try setOutputVolume(floatVolume)

        var result = "[OK] Volume set to \(clamped)%"
        if clamped != args.volume {
            result += " (clamped from \(args.volume))"
        }

        if let mute = args.mute {
            let shouldMute = mute == 1
            do {
                try setOutputMute(shouldMute)
                result += shouldMute ? ", muted" : ", unmuted"
            } catch {
                result += " (warning: volume changed but mute toggle failed: \(error.localizedDescription))"
            }
        }

        return result
    }
}

// MARK: - CoreAudio Helpers

private func getDefaultOutputDeviceID() throws -> AudioDeviceID {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &deviceID
    )
    guard status == noErr else {
        throw ToolError.operationFailed("Cannot access audio output device (error \(status)).")
    }
    return deviceID
}

private func getOutputVolume() throws -> (Float32, Bool) {
    let deviceID = try getDefaultOutputDeviceID()

    var volume = Float32(0)
    var volumeSize = UInt32(MemoryLayout<Float32>.size)
    var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let volStatus = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &volumeSize, &volume)
    guard volStatus == noErr else {
        throw ToolError.operationFailed("Cannot read volume level (error \(volStatus)).")
    }

    var muted = UInt32(0)
    var muteSize = UInt32(MemoryLayout<UInt32>.size)
    var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    // Mute property may not exist on all devices — treat failure as unmuted
    let muteStatus = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &muted)
    let isMuted = (muteStatus == noErr) && (muted != 0)

    return (volume, isMuted)
}

private func setOutputVolume(_ volume: Float32) throws {
    let deviceID = try getDefaultOutputDeviceID()
    var vol = volume
    var size = UInt32(MemoryLayout<Float32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    guard status == noErr else {
        throw ToolError.operationFailed("Cannot set volume (error \(status)). The device may not support volume control.")
    }
}

private func setOutputMute(_ mute: Bool) throws {
    let deviceID = try getDefaultOutputDeviceID()
    var muted = UInt32(mute ? 1 : 0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted)
    guard status == noErr else {
        throw ToolError.operationFailed("Cannot set mute state (error \(status)). The device may not support mute.")
    }
}

// MARK: - Appearance

struct ToggleAppearanceTool: AgentTool {
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

// MARK: - Reminders

struct CreateReminderTool: AgentTool {
    let definition = ToolDefinition(
        name: "create_reminder",
        description: """
            Create a reminder in the macOS Reminders app via EventKit. \
            Requires Reminders permission — will prompt on first use. \
            Optionally set a due date (ISO 8601 format: "2024-12-31T09:00:00"). \
            The reminder is added to the user's default reminder list.
            """,
        parameters: .schemaObject(
            properties: [
                "title": .stringProperty("Reminder title (required)"),
                "notes": .stringProperty("Optional notes/body text for the reminder"),
                "due_date": .stringProperty("Optional due date in ISO 8601 format (e.g. '2024-12-31T09:00:00'). Omit for no due date."),
                "priority": .intProperty("Priority: 0 = none (default), 1 = high, 5 = medium, 9 = low"),
            ],
            required: ["title"]
        )
    )

    private struct Args: Decodable {
        let title: String
        let notes: String?
        let dueDate: String?
        let priority: Int?
    }

    private static let store = EKEventStore()

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        guard !args.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.invalidArguments("Reminder title cannot be empty.")
        }

        let store = Self.store

        // Request access
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }

        guard granted else {
            throw ToolError.operationFailed(
                "Reminders permission denied. Enable in System Settings → Privacy & Security → Reminders → Sage."
            )
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = args.title
        reminder.notes = args.notes
        reminder.priority = args.priority ?? 0
        reminder.calendar = store.defaultCalendarForNewReminders()

        // Parse due date if provided
        if let dueDateStr = args.dueDate, !dueDateStr.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            // Try with fractional seconds first, then without
            var date = formatter.date(from: dueDateStr)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: dueDateStr)
            }
            if date == nil {
                // Try basic format without timezone: "2024-12-31T09:00:00"
                let basic = ISO8601DateFormatter()
                basic.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
                date = basic.date(from: dueDateStr)
            }

            guard let parsedDate = date else {
                throw ToolError.invalidArguments(
                    "Invalid due_date format: '\(dueDateStr)'. Use ISO 8601 (e.g. '2024-12-31T09:00:00' or '2024-12-31T09:00:00Z')."
                )
            }

            let calendar = Calendar.current
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: parsedDate
            )
            reminder.dueDateComponents = components
        }

        try store.save(reminder, commit: true)

        var result = "[OK] Reminder created: \"\(args.title)\""
        if let dueDate = args.dueDate {
            result += " (due: \(dueDate))"
        }
        return result
    }
}

// MARK: - Screenshot

struct TakeScreenshotTool: AgentTool {
    let definition = ToolDefinition(
        name: "take_screenshot",
        description: """
            Capture a screenshot and save it to a file under ~/. \
            Modes: "screen" captures the entire main screen, "window" captures the frontmost window. \
            Returns the file path of the saved PNG image. \
            The file can be referenced in subsequent tool calls or shown to the user. \
            Default save location: ~/Desktop/sage_screenshot_<timestamp>.png
            """,
        parameters: .schemaObject(
            properties: [
                "mode": .stringProperty("Capture mode: 'screen' (default) or 'window'"),
                "path": .stringProperty("Optional save path (must be under ~/). Defaults to ~/Desktop/sage_screenshot_<timestamp>.png"),
            ],
            required: []
        )
    )

    private struct Args: Decodable {
        let mode: String?
        let path: String?
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let captureMode = (args.mode ?? "screen").lowercased()

        guard ["screen", "window"].contains(captureMode) else {
            throw ToolError.invalidArguments("Invalid mode '\(args.mode ?? "")'. Use 'screen' or 'window'.")
        }

        // Determine save path
        let savePath: URL
        if let customPath = args.path {
            savePath = try PathGuard.resolveAllowed(customPath)
        } else {
            let timestamp = Self.timestampFormatter.string(from: Date())
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            savePath = desktop.appendingPathComponent("sage_screenshot_\(timestamp).png")
        }

        // Ensure parent directory exists
        try FileManager.default.createDirectory(
            at: savePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Try CGWindowList API first for non-interactive capture
        let captured = try await captureWithCGWindow(mode: captureMode, savePath: savePath)
        if captured {
            let attrs = try? FileManager.default.attributesOfItem(atPath: savePath.path)
            let size = (attrs?[.size] as? Int) ?? 0
            return "[OK] Screenshot saved to \(savePath.path) (\(size) bytes)"
        }

        // Fallback: screencapture CLI (only for screen mode — window mode requires interactive selection)
        if captureMode == "screen" {
            let result = try await runScreencapture(arguments: ["-x", savePath.path])
            if result == 0, FileManager.default.fileExists(atPath: savePath.path) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: savePath.path)
                let size = (attrs?[.size] as? Int) ?? 0
                return "[OK] Screenshot saved to \(savePath.path) (\(size) bytes)"
            }
        }

        let hint = captureMode == "window"
            ? "Window capture failed — no visible window found for the frontmost app (excluding Sage)."
            : "Screenshot failed."
        throw ToolError.operationFailed(
            "\(hint) Ensure Sage has Screen Recording permission in System Settings → Privacy & Security → Screen Recording → Sage."
        )
    }

    private static let sageBundleID = "mozheng.Sage"

    private func captureWithCGWindow(mode: String, savePath: URL) async throws -> Bool {
        return await MainActor.run {
            let image: CGImage?

            if mode == "window" {
                // Find the frontmost window, excluding Sage itself
                let windowList = CGWindowListCopyWindowInfo(
                    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
                ) as? [[String: Any]] ?? []

                // Filter out Sage's own windows and find the topmost non-Sage window
                let candidateWindows = windowList.filter { info in
                    guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                          let layer = info[kCGWindowLayer as String] as? Int,
                          layer == 0 // normal window layer
                    else { return false }
                    // Exclude Sage windows by bundle ID or name
                    if let pid = info[kCGWindowOwnerPID as String] as? Int32,
                       let app = NSRunningApplication(processIdentifier: pid),
                       app.bundleIdentifier == Self.sageBundleID {
                        return false
                    }
                    return !ownerName.isEmpty
                }

                guard let frontWindow = candidateWindows.first,
                      let windowID = frontWindow[kCGWindowNumber as String] as? CGWindowID
                else { return false }
                image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming])
            } else {
                // Capture entire main display
                image = CGDisplayCreateImage(CGMainDisplayID())
            }

            guard let cgImage = image else { return false }

            // Save as PNG
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let pngData = rep.representation(using: .png, properties: [:]) else { return false }

            do {
                try pngData.write(to: savePath)
                return true
            } catch {
                return false
            }
        }
    }

    private func runScreencapture(arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments

            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ToolError.operationFailed(
                    "Failed to run screencapture: \(error.localizedDescription)"
                ))
            }
        }
    }
}
