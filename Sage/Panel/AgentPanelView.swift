import SwiftUI

struct AgentPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session

    var body: some View {
        AgentWorkspaceView()
            .frame(minWidth: 560, minHeight: 440)
            .background(Color(nsColor: .windowBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(session.isGeneral ? "Sage" : session.agent.state.focusTitle)
            .sageScaledTypography()
            .sageAccessibilityObservation()
    }
}
