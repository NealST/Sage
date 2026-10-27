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
    /// Supply sources: default + per-phase model selection, cloud catalog,
    /// and local (MLX) downloads. Connection keeps the transport-layer
    /// fields; this pane owns which models run.
    case models
    case capabilities
    /// General behavior (login item). Schedule management itself lives in
    /// the Dashboard — the case name must not promise schedule settings.
    case startup
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: "Connection"
        case .models: "Models"
        case .capabilities: "Capabilities"
        case .startup: "General"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: "network"
        case .models: SageDesign.Symbol.modelLocal
        case .capabilities: "puzzlepiece.extension"
        case .startup: "gearshape"
        case .privacy: "hand.raised"
        }
    }
}
