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
                "Accessibility permission not granted. Enable in System Settings → Privacy & Security → Accessibility → Sage."
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
            let axElement = element as! AXUIElement

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
                "Accessibility permission not granted. Enable in System Settings → Privacy & Security → Accessibility → Sage."
            )
        }

        return try await MainActor.run {
            guard let focusedApp = NSWorkspace.shared.frontmostApplication else {
                throw ToolError.operationFailed(
                    "No frontmost application found. Bring an app to the foreground first."
                )
            }

            // Prevent typing into Sage's own window
            if focusedApp.bundleIdentifier == Self.sageBundleID {
                throw ToolError.operationFailed(
                    "Cannot type into Sage's own window. Bring the target application to the foreground first."
                )
            }

            let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)

            // Get the focused UI element
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
                    "No focused element in \(focusedApp.localizedName ?? "the app"). Click on a text field first."
                )
            }

            let element = ref as! AXUIElement

            // Check if the element's role supports text input
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            // Verify the element is editable by checking if AXValue is settable
            var isSettable: DarwinBoolean = false
            let settableResult = AXUIElementIsAttributeSettable(
                element,
                kAXValueAttribute as CFString,
                &isSettable
            )

            // Strategy 1: Set selected text (works for replacing selection or inserting at cursor)
            var lastAXError: AXError?

            let selectedTextSettable: DarwinBoolean = {
                var s: DarwinBoolean = false
                AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &s)
                return s
            }()

            if selectedTextSettable.boolValue {
                let setResult = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextAttribute as CFString,
                    args.text as CFTypeRef
                )
                if setResult == .success {
                    return "[OK] Typed \(args.text.count) characters into \(focusedApp.localizedName ?? "app")"
                }
                lastAXError = setResult
            }

            // Strategy 2: If selected text attribute isn't settable, try setting the full value
            // (only for simple single-value fields like search bars — replaces entire field content)
            if settableResult == .success, isSettable.boolValue {
                let textRoles = ["AXTextField", "AXSearchField", "AXComboBox"]
                if textRoles.contains(role) {
                    let setResult = AXUIElementSetAttributeValue(
                        element,
                        kAXValueAttribute as CFString,
                        args.text as CFTypeRef
                    )
                    if setResult == .success {
                        return "[OK] Set value to \(args.text.count) characters in \(focusedApp.localizedName ?? "app")"
                    }
                    lastAXError = setResult
                }
            }

            // If we get here, the element doesn't support text input
            let roleSuffix = role.isEmpty ? "" : " (role: \(role))"
            let errorDetail: String
            if let axErr = lastAXError {
                errorDetail = " AX error: \(axErr.rawValue)."
            } else {
                errorDetail = ""
            }
            throw ToolError.operationFailed(
                "Focused element is not editable\(roleSuffix).\(errorDetail) Click on a text field or editor first."
            )
        }
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

            // Report active window frame if accessibility is available
            if AXIsProcessTrusted(),
               let app = NSWorkspace.shared.frontmostApplication
            {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                var windowRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(
                    appElement,
                    kAXFocusedWindowAttribute as CFString,
                    &windowRef
                )
                if result == .success,
                   let window = windowRef,
                   CFGetTypeID(window) == AXUIElementGetTypeID()
                {
                    let winElement = window as! AXUIElement
                    var posRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(winElement, kAXPositionAttribute as CFString, &posRef)
                    AXUIElementCopyAttributeValue(winElement, kAXSizeAttribute as CFString, &sizeRef)

                    var point = CGPoint.zero
                    var size = CGSize.zero
                    if let posRef, CFGetTypeID(posRef) == AXValueGetTypeID(),
                       AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
                       let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID(),
                       AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
                    {
                        lines.append("")
                        lines.append("active_window:")
                        lines.append("  app: \(app.localizedName ?? "(unknown)")")
                        lines.append("  position: (\(Int(point.x)), \(Int(point.y)))")
                        lines.append("  size: \(Int(size.width))x\(Int(size.height))")
                    }
                }
            }

            return lines.joined(separator: "\n")
        }
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
                   CFGetTypeID(window) == AXUIElementGetTypeID()
                {
                    var titleValue: CFTypeRef?
                    let titleResult = AXUIElementCopyAttributeValue(
                        window as! AXUIElement,
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
