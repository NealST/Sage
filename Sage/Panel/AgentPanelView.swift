//
//  AgentPanelView.swift
//  Sage
//

import SwiftUI

struct AgentPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        AgentWorkspaceView()
        .frame(minWidth: 560, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sage")
    }
}

#Preview {
    AgentPanelView()
        .environment(AppState())
}
