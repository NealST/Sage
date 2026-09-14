//
//  HotkeyManager.swift
//  Sage
//

import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

extension Notification.Name {
    static let sageToggleAgentWindow = Notification.Name("sage.toggleAgentWindow")
}

/// A user-recordable global shortcut, stored as the physical key plus Carbon
/// modifier mask so it can be re-registered without another capture.
struct SageHotkey: Codable, Equatable, Sendable {
    /// Virtual key code (kVK_*), e.g. kVK_Space.
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey | shiftKey | optionKey | controlKey).
    var carbonModifiers: UInt32
    /// Display form of the key alone — "Space", "S", ",".
    var keyLabel: String

    /// Factory default: ⌘⇧Space (works without Accessibility permission).
    static let standard = SageHotkey(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "Space"
    )

    /// Glyph form matching macOS menu display order: ⌃⌥⇧⌘ + key.
    var symbolRepresentation: String {
        var glyphs = ""
        if carbonModifiers & UInt32(controlKey) != 0 { glyphs += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { glyphs += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { glyphs += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { glyphs += "⌘" }
        return glyphs + keyLabel
    }

    /// SwiftUI menu shortcut mirroring the Carbon registration. `nil` when the
    /// recorded key has no KeyEquivalent (rare punctuation) — callers skip the
    /// menu hint rather than showing a wrong one.
    var keyboardShortcut: KeyboardShortcut? {
        let modifiers: SwiftUICore.EventModifiers = modifierFlags
        switch keyCode {
        case UInt32(kVK_Space):
            return KeyboardShortcut(.space, modifiers: modifiers)
        case UInt32(kVK_Return):
            return KeyboardShortcut(.return, modifiers: modifiers)
        case UInt32(kVK_Tab):
            return KeyboardShortcut(.tab, modifiers: modifiers)
        case UInt32(kVK_Delete):
            return KeyboardShortcut(.delete, modifiers: modifiers)
        default:
            guard let character = keyLabel.first else { return nil }
            return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
        }
    }

    private var modifierFlags: SwiftUICore.EventModifiers {
        var flags: SwiftUICore.EventModifiers = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}

/// Registers the global hot key via Carbon (works without Accessibility
/// permission). The combination is user-configurable and persisted; changing
/// it re-registers atomically and falls back to the previous one on conflict.
final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()

    private static let storageKey = "sage.globalHotkey"

    /// Currently registered (or attempted) hotkey.
    private(set) var current: SageHotkey

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let hotkey = try? JSONDecoder().decode(SageHotkey.self, from: data) {
            current = hotkey
        } else {
            current = .standard
        }
    }

    @discardableResult
    func start() -> Bool {
        installHandlerIfNeeded()
        guard hotKeyRef == nil else { return true }
        return register(current)
    }

    func stop() {
        unregisterHotKey()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    /// Re-registers with a new combination. On failure the previous hotkey is
    /// restored and `false` is returned so the UI can explain the conflict.
    @discardableResult
    func update(_ hotkey: SageHotkey) -> Bool {
        guard hotkey != current else { return true }
        unregisterHotKey()
        guard register(hotkey) else {
            _ = register(current)
            return false
        }
        current = hotkey
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        return true
    }

    /// Drops the stored combination back to ⌘⇧Space and re-registers.
    @discardableResult
    func resetToDefault() -> Bool {
        update(.standard)
    }

    /// Temporarily releases the system hotkey (while recording a replacement)
    /// without tearing down the Carbon event handler.
    func suspend() {
        unregisterHotKey()
    }

    func resume() {
        guard handlerRef != nil, hotKeyRef == nil else { return }
        _ = register(current)
    }

    // MARK: - Carbon plumbing

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        _ = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .sageToggleAgentWindow, object: nil)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }

    @discardableResult
    private func register(_ hotkey: SageHotkey) -> Bool {
        guard hotKeyRef == nil else { return true }
        let hotKeyID = EventHotKeyID(signature: OSType(0x53414745), id: 1) // 'SAGE'
        return RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        ) == noErr
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
