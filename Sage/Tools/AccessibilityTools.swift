//
//  AccessibilityTools.swift
//  Sage
//

import AppKit
import ApplicationServices
import Foundation

nonisolated struct GetSelectedTextTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_selected_text",
        description: """
            Get the currently selected text in the frontmost application via macOS Accessibility API. \
            Returns the selected text, or "(no selection)" if nothing is selected. \
            Requires Accessibility permission (System Settings → Privacy & Security → Accessibility → Sage). \
            Fails with a clear message if permission is not granted.
            """,
        parameters: .schemaObject(properties: [:])
    )

    func call(argumentsJSON: String) async throws -> String {
        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            throw ToolError.operationFailed(
                """
                Accessibility permission not granted. Enable in System Settings → \
                Privacy & Security → Accessibility → Sage.
                """
            )
        }

        return await MainActor.run {
            guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
                return "(no frontmost application)"
            }

            let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

            // Get the focused UI element
            var focusedElement: CFTypeRef?
            let focusResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElement
            )

            guard focusResult == .success,
                  let element = focusedElement,
                  CFGetTypeID(element) == AXUIElementGetTypeID()
            else {
                return "(no focused element)"
            }

            // Get selected text from the focused element
            let axElement = unsafeDowncast(element, to: AXUIElement.self)

            // Try getting selected text directly
            var selectedText: CFTypeRef?
            let textResult = AXUIElementCopyAttributeValue(
                axElement,
                kAXSelectedTextAttribute as CFString,
                &selectedText
            )

            if textResult == .success, let text = selectedText as? String, !text.isEmpty {
                // Cap at 10K characters to avoid overwhelming context
                if text.count > 10_000 {
                    return String(text.prefix(10_000)) + "\n… (selection truncated at 10,000 characters)"
                }
                return text
            }

            return "(no selection)"
        }
    }
}

nonisolated struct TypeTextTool: AgentTool {
    let definition = ToolDefinition(
        name: "type_text",
        description: """
            Insert text at the current cursor position in the frontmost application, or replace \
            the current selection if text is selected. Uses macOS Accessibility API. \
            Requires Accessibility permission (System Settings → Privacy & Security → Accessibility → Sage). \
            Will not type into Sage's own window. Maximum 50,000 characters per call. \
            Use with get_selected_text for a "select → process → replace" workflow.
            """,
        parameters: .schemaObject(
            properties: [
                "text": .stringProperty("Text to insert at cursor or replace current selection with"),
            ],
            required: ["text"]
        )
    )

    private struct Args: Decodable {
        let text: String
    }

    private static let maxChars = 50_000
    private static let sageBundleID = "mozheng.Sage"

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        guard !args.text.isEmpty else {
            throw ToolError.invalidArguments("Text cannot be empty. To clear a selection, use a single space.")
        }

        guard args.text.count <= Self.maxChars else {
            throw ToolError.invalidArguments(
                "Text too long (\(args.text.count) characters). Maximum is \(Self.maxChars) characters per call."
            )
        }

        guard AXIsProcessTrusted() else {
            throw ToolError.operationFailed(
                """
                Accessibility permission not granted. Enable in System Settings → \
                Privacy & Security → Accessibility → Sage.
                """
            )
        }

        return try await MainActor.run {
            try Self.typeIntoFrontmostApp(args.text)
        }
    }

    @MainActor
    static func typeIntoFrontmostApp(_ text: String) throws -> String {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
            throw ToolError.operationFailed(
                "No frontmost application found. Bring an app to the foreground first."
            )
        }
        if focusedApp.bundleIdentifier == sageBundleID {
            throw ToolError.operationFailed(
                "Cannot type into Sage's own window. Bring the target application to the foreground first."
            )
        }
        let element = try focusedElement(in: focusedApp)
        if let typed = trySetSelectedText(text, on: element, appName: focusedApp.localizedName) {
            return typed
        }
        if let replaced = trySetFieldValue(text, on: element, appName: focusedApp.localizedName) {
            return replaced
        }
        throw ToolError.operationFailed(
            "Focused element is not editable. Click on a text field or editor first."
        )
    }

    @MainActor
    static func focusedElement(in app: NSRunningApplication) throws -> AXUIElement {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusResult == .success,
              let ref = focusedRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID()
        else {
            throw ToolError.operationFailed(
                "No focused element in \(app.localizedName ?? "the app"). Click on a text field first."
            )
        }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    @MainActor
    static func trySetSelectedText(_ text: String, on element: AXUIElement, appName: String?) -> String? {
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        guard settable.boolValue else { return nil }
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setResult == .success else { return nil }
        return "[OK] Typed \(text.count) characters into \(appName ?? "app")"
    }

    @MainActor
    static func trySetFieldValue(_ text: String, on element: AXUIElement, appName: String?) -> String? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        )
        guard settableResult == .success, isSettable.boolValue else { return nil }
        let textRoles = ["AXTextField", "AXSearchField", "AXComboBox"]
        guard textRoles.contains(role) else { return nil }
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        guard setResult == .success else { return nil }
        return "[OK] Set value to \(text.count) characters in \(appName ?? "app")"
    }
}

nonisolated struct GetScreenInfoTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_screen_info",
        description: """
            Get information about connected displays: resolution, scale factor (Retina), \
            and whether it is the main screen. Also reports the number of active displays \
            and the frontmost app's window frame if Accessibility permission is available. \
            Does not require any special permissions for basic screen info.
            """,
        parameters: .schemaObject(properties: [:])
    )

    func call(argumentsJSON: String) async throws -> String {
        await MainActor.run {
            let screens = NSScreen.screens
            guard !screens.isEmpty else {
                return "(no displays detected)"
            }

            var lines: [String] = []
            lines.append("displays: \(screens.count)")

            for (index, screen) in screens.enumerated() {
                let frame = screen.frame
                let visibleFrame = screen.visibleFrame
                let scale = screen.backingScaleFactor
                let isMain = (screen == NSScreen.main)
                let label = isMain ? " (main)" : ""

                lines.append("")
                lines.append("display_\(index + 1)\(label):")
                lines.append("  resolution: \(Int(frame.width))x\(Int(frame.height))")
                lines.append("  scale: \(scale)x\(scale > 1 ? " (Retina)" : "")")
                lines.append("  visible_area: \(Int(visibleFrame.width))x\(Int(visibleFrame.height))")
                lines.append("  origin: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")

                if let name = screen.localizedName as String? {
                    lines.append("  name: \(name)")
                }
            }

            lines.append(contentsOf: Self.activeWindowLines())
            return lines.joined(separator: "\n")
        }
    }

    @MainActor
    static func activeWindowLines() -> [String] {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )
        guard result == .success,
              let window = windowRef,
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return [] }
        let winElement = unsafeDowncast(window, to: AXUIElement.self)
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(winElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(winElement, kAXSizeAttribute as CFString, &sizeRef)
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(posRef, to: AXValue.self), .cgPoint, &point),
              let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size) else {
            return []
        }
        return [
            "",
            "active_window:",
            "  app: \(app.localizedName ?? "(unknown)")",
            "  position: (\(Int(point.x)), \(Int(point.y)))",
            "  size: \(Int(size.width))x\(Int(size.height))",
        ]
    }
}

nonisolated struct GetFrontmostAppTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_frontmost_app",
        description: """
            Get information about the currently active (frontmost) application. \
            Returns: app name, bundle ID, pid, and the title of the focused window. \
            Basic info (name, bundle ID, pid) works without Accessibility permission. \
            Window title requires Accessibility permission — omitted silently if not granted.
            """,
        parameters: .schemaObject(properties: [:])
    )

    func call(argumentsJSON: String) async throws -> String {
        await MainActor.run {
            guard let app = NSWorkspace.shared.frontmostApplication else {
                return "(no frontmost application)"
            }

            var lines: [String] = []
            lines.append("app: \(app.localizedName ?? "(unknown)")")
            lines.append("bundle_id: \(app.bundleIdentifier ?? "(unknown)")")

            // Try to get window title via Accessibility (best effort)
            if AXIsProcessTrusted() {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var windowValue: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(
                    appElement,
                    kAXFocusedWindowAttribute as CFString,
                    &windowValue
                )
                if result == .success,
                   let window = windowValue,
                   CFGetTypeID(window) == AXUIElementGetTypeID() {
                    var titleValue: CFTypeRef?
                    let titleResult = AXUIElementCopyAttributeValue(
                        unsafeDowncast(window, to: AXUIElement.self),
                        kAXTitleAttribute as CFString,
                        &titleValue
                    )
                    if titleResult == .success, let title = titleValue as? String {
                        lines.append("window_title: \(title)")
                    }
                }
            }

            lines.append("pid: \(app.processIdentifier)")
            return lines.joined(separator: "\n")
        }
    }
}
