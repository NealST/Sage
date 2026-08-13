//
//  ScreenshotTool.swift
//  Sage
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Screenshot

struct TakeScreenshotTool: AgentTool {
    let definition = ToolDefinition(
        name: "take_screenshot",
        description: """
            Capture a screenshot and save it to a PNG under ~/. \
            Modes: "screen" captures the main display; "window" captures the frontmost visible \
            window of another app (skips Sage itself — useful when Sage has focus). \
            Returns the saved file path. Default: ~/Desktop/sage_screenshot_<timestamp>.png. \
            Requires Screen Recording permission.
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

        // Use screencapture CLI (CGWindowListCreateImage is unavailable on newer macOS).
        // Window mode: resolve a CGWindowID then capture with -l.
        let captureArgs: [String]
        if captureMode == "window" {
            guard let windowID = Self.frontmostCapturableWindowID() else {
                throw ToolError.operationFailed(
                    "No capturable window found (excluding Sage). Bring another app’s window to the front and retry."
                )
            }
            captureArgs = ["-x", "-o", "-l", String(windowID), savePath.path]
        } else {
            captureArgs = ["-x", savePath.path]
        }

        let status = try await runScreencapture(arguments: captureArgs)
        if status == 0, FileManager.default.fileExists(atPath: savePath.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: savePath.path)
            let size = (attrs?[.size] as? Int) ?? 0
            let modeLabel = captureMode == "window" ? "Window screenshot" : "Screenshot"
            return "[OK] \(modeLabel) saved to \(savePath.path) (\(size) bytes)"
        }

        throw ToolError.operationFailed(
            "Screenshot failed. Ensure Sage has Screen Recording permission in System Settings → Privacy & Security → Screen Recording → Sage."
        )
    }

    /// Front-to-back on-screen windows; prefer the frontmost non-Sage app, else any other app.
    private static func frontmostCapturableWindowID() -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        let sagePID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let preferredPID: pid_t? = {
            guard let frontPID, frontPID != sagePID else { return nil }
            return frontPID
        }()

        var fallback: CGWindowID?

        for info in infoList {
            guard let pidValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(pidValue.int32Value)
            if pid == sagePID { continue }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }

            if let bounds = info[kCGWindowBounds as String] as? [String: Any] {
                let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
                let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
                // Skip menu bar extras / tiny panels.
                guard width >= 80, height >= 80 else { continue }
            }

            guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let windowID = CGWindowID(number.uint32Value)

            if let preferredPID, pid == preferredPID {
                return windowID
            }
            if fallback == nil {
                fallback = windowID
            }
        }

        return fallback
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
