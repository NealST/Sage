//
//  SettingsHotkeySection.swift
//  Sage
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Recorder row for the global summon hotkey. Click the field, press a new
/// combination (must include ⌘ or ⌃ so typing elsewhere is never hijacked),
/// press Esc to cancel. Conflicts with other apps fall back to the previous
/// combination and are explained in the footer.
struct SettingsHotkeySection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sageTypography) private var type
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var validationHint: String?
    /// Recorder affordance before click — the field reads as static text otherwise.
    @State private var hoveringRecorder = false

    var body: some View {
        Section {
            LabeledContent("Global Hotkey") {
                HStack(spacing: SageDesign.Spacing.small) {
                    recorderField
                    if appState.globalHotkey != .standard {
                        Button("Restore Defaults") {
                            applyHotkey(.standard)
                        }
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.extraSmall) {
                if appState.hotkeyRegistrationFailed {
                    Label(
                        "\(appState.globalHotkey.symbolRepresentation) could not be registered. Another app may already use it; record a different combination.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(SageDesign.Palette.warningText)
                } else if let validationHint {
                    Label(validationHint, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(SageDesign.Palette.warningText)
                }
                Text("Summon the Sage window from any app. Click the shortcut, then press a new combination; press Esc to cancel. Shortcuts other apps rely on (⌘Q, ⌘Space…) are refused.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { endRecording() }
    }

    // MARK: - Recorder field

    private var recorderField: some View {
        Button {
            if isRecording {
                endRecording()
            } else {
                beginRecording()
            }
        } label: {
            Text(isRecording ? "Type a shortcut…" : appState.globalHotkey.symbolRepresentation)
                .sageFont(type.body, weight: .medium)
                .foregroundStyle(isRecording ? Color.secondary : Color.primary)
                .frame(minWidth: 96)
                .padding(.horizontal, SageDesign.Spacing.small)
                .padding(.vertical, SageDesign.Spacing.extraSmall)
                .background(
                    RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                        .fill(
                            Color.primary.opacity(
                                isRecording
                                    ? SageDesign.Chrome.pillFillOpacity
                                    : (hoveringRecorder
                                       ? SageDesign.Chrome.pillFillOpacity
                                       : SageDesign.Chrome.fillOpacity)
                            )
                        )
                )
                .overlay {
                    if isRecording {
                        RoundedRectangle(cornerRadius: SageDesign.Glass.chip, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(SageDesign.Chrome.accentRingOpacity),
                                lineWidth: 1
                            )
                    }
                }
                .onHover { hoveringRecorder = $0 }
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut")
        .accessibilityLabel("Global hotkey")
        .accessibilityValue(appState.globalHotkey.symbolRepresentation)
        .accessibilityHint(isRecording ? "Press a new key combination, or Escape to cancel" : "Click to record a new shortcut")
    }

    // MARK: - Recording lifecycle

    private func beginRecording() {
        isRecording = true
        validationHint = nil
        // Release the live registration so recording the current combination
        // doesn't summon the window mid-capture.
        HotkeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecordedEvent(event)
        }
    }

    private func endRecording() {
        guard isRecording else { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        HotkeyManager.shared.resume()
    }

    // MARK: - Event capture

    /// Consumes every key while recording (`nil` return) so nothing leaks to
    /// the form, the window, or the menu bar.
    private func handleRecordedEvent(_ event: NSEvent) -> NSEvent? {
        // Pure modifier presses arrive as keyDown without a usable key —
        // keep waiting for the actual character key.
        if isModifierKeyCode(Int(event.keyCode)) { return nil }
        if event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            return nil
        }

        let carbonModifiers = Self.carbonMask(
            event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        guard carbonModifiers & UInt32(cmdKey | controlKey) != 0 else {
            validationHint = "Include ⌘ or ⌃. A combination without them would fire while typing."
            return nil
        }
        if let conflict = Self.reservedSystemShortcutReason(
            keyCode: Int(event.keyCode),
            carbonModifiers: carbonModifiers,
            character: event.charactersIgnoringModifiers
        ) {
            validationHint = conflict
            return nil
        }

        let hotkey = SageHotkey(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers,
            keyLabel: Self.keyLabel(for: event)
        )
        endRecording()
        applyHotkey(hotkey)
        return nil
    }

    private func applyHotkey(_ hotkey: SageHotkey) {
        guard HotkeyManager.shared.update(hotkey) else {
            appState.hotkeyRegistrationFailed = true
            return
        }
        appState.globalHotkey = hotkey
        appState.hotkeyRegistrationFailed = false
        validationHint = nil
    }

    // MARK: - Reserved combinations

    /// System-reserved combinations from the HIG standard-shortcut table. A
    /// Carbon registration is global and outranks app menus, so accepting one
    /// of these would break it everywhere — ⌘Q would stop quitting every app.
    /// Returning a reason refuses the recording; the recorder keeps listening.
    private static func reservedSystemShortcutReason(
        keyCode: Int,
        carbonModifiers: UInt32,
        character: String?
    ) -> String? {
        let hasCmd = carbonModifiers & UInt32(cmdKey) != 0
        let hasCtrl = carbonModifiers & UInt32(controlKey) != 0
        let hasShift = carbonModifiers & UInt32(shiftKey) != 0

        switch keyCode {
        case kVK_Space:
            // Spotlight and input-source switching: ⌘Space, ⌃Space, ⌥⌘Space,
            // ⌃⌘Space, ⌃⌥Space. ⇧ variants are free (⌘⇧Space is the default).
            if (hasCmd || hasCtrl) && !hasShift {
                return "macOS uses this for Spotlight or switching input sources. Keep ⇧ in the combination, or pick another key."
            }

        case kVK_Tab:
            // ⌘Tab / ⇧⌘Tab cycle apps; ⌃Tab cycles control groups in dialogs.
            if hasCmd || hasCtrl {
                return "Tab with ⌘ or ⌃ switches apps or dialogs. Pick another key."
            }

        case kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6:
            // Screenshots: ⇧⌘3/4 (plus ⌃ for clipboard copies), ⇧⌘5, ⇧⌘6.
            if hasCmd && hasShift {
                return "⇧⌘3 through ⇧⌘6 take screenshots. Pick another key."
            }

        case kVK_F5:
            if carbonModifiers == UInt32(cmdKey) {
                return "⌘F5 turns VoiceOver on or off. Pick another key."
            }

        default:
            break
        }

        // Bare ⌘ + a typeable character (⌘Q, ⌘S, ⌘1…) is a standard command in
        // nearly every app. ⇧ or ⌥ variants stay available.
        if carbonModifiers == UInt32(cmdKey),
           let character,
           character.unicodeScalars.count == 1,
           let scalar = character.unicodeScalars.first,
           (0x21...0x7E).contains(scalar.value) {
            return "⌘ plus a letter or number is a standard command (Copy, Save, Quit…) in most apps. Add ⇧ or ⌥."
        }
        return nil
    }

    // MARK: - Key naming

    private static func keyLabel(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        case kVK_Delete: "Delete"
        case kVK_ForwardDelete: "Forward Delete"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Home: "Home"
        case kVK_End: "End"
        case kVK_PageUp: "Page Up"
        case kVK_PageDown: "Page Down"
        default:
            fKeyLabel(Int(event.keyCode))
                ?? event.charactersIgnoringModifiers.flatMap(\.first).map(String.init)
                ?? "Key \(event.keyCode)"
        }
    }

    private static func fKeyLabel(_ keyCode: Int) -> String? {
        let functionKeys: [Int: String] = [
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
            0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x4F: "F18",
            0x50: "F19",
        ]
        return functionKeys[keyCode]
    }

    private func isModifierKeyCode(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    private static func carbonMask(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }
}
