//
//  HotkeyManager.swift
//  Sage
//

import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let sageToggleAgentWindow = Notification.Name("sage.toggleAgentWindow")
}

/// Registers ⌘⇧Space via Carbon hot keys (works without Accessibility permission).
final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    @discardableResult
    func start() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
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

        guard status == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x53414745), id: 1) // 'SAGE'
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return hotKeyStatus == noErr
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
