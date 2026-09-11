//
//  SettingsPane.swift
//  Sage
//
//  Sidebar destinations for the Settings window. Add a case here when a
//  new pane ships — SettingsView’s switch must handle it.
//

import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case connection
    case capabilities
    /// Startup behavior (login item). Schedule management itself lives in
    /// the Dashboard — the case name must not promise schedule settings.
    case startup
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: "Connection"
        case .capabilities: "Capabilities"
        case .startup: "Startup"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: "network"
        case .capabilities: "puzzlepiece.extension"
        case .startup: "power"
        case .privacy: "hand.raised"
        }
    }
}
