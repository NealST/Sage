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
    case schedules
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: "Connection"
        case .capabilities: "Capabilities"
        case .schedules: "Schedules"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: "network"
        case .capabilities: "puzzlepiece.extension"
        case .schedules: "clock"
        case .privacy: "hand.raised"
        }
    }
}
