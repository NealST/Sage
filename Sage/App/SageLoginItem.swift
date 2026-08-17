//
//  SageLoginItem.swift
//  Sage
//
//  Open Sage at login so in-process schedules can fire after a restart.
//

import ServiceManagement

enum SageLoginItem {
    /// Whether the main app is registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user must allow Sage in System Settings → Login Items.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the main app as a login item.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Opens System Settings to Login Items so the user can allow Sage.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
