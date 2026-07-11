//
//  AgentPanelView.swift
//  Sage
//

import SwiftUI

struct AgentPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            AgentSidebarView(searchText: $searchText)
                .navigationSplitViewColumnWidth(min: 200, ideal: SageDesign.Panel.sidebarWidth, max: 320)
        } detail: {
            AgentChatView()
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sage")
    }
}

#Preview {
    AgentPanelView()
        .environment(AppState())
}
