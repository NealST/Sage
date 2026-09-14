import SwiftUI

struct AgentPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(AgentSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Content-level presentation scale. The window itself only alpha-fades
    /// (AppKit has no public window transform), so the content adds the
    /// dimensional half of the summon — 0.98 → 1 over the same 0.18s, and
    /// mirrored back down on hide. False whenever the window is hidden, so
    /// every appearance starts from the scaled-down origin.
    @State private var windowPresented = false

    var body: some View {
        AgentWorkspaceView()
            .scaleEffect(presentationScale)
            .frame(
                minWidth: SageDesign.Panel.minWidth,
                minHeight: SageDesign.Panel.minHeight
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(session.isGeneral ? "Sage" : session.agent.state.focusTitle)
            .sageScaledTypography()
            .sageAccessibilityObservation()
            .onReceive(NotificationCenter.default.publisher(for: .sageWindowDidPresent)) { note in
                guard note.object as? AgentSession.Kind == session.kind else { return }
                withAnimation(.easeOut(duration: SageDesign.Motion.windowFadeInDuration)) {
                    windowPresented = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sageWindowWillUnpresent)) { note in
                guard note.object as? AgentSession.Kind == session.kind else { return }
                withAnimation(.easeOut(duration: SageDesign.Motion.windowFadeOutDuration)) {
                    windowPresented = false
                }
            }
    }

    private var presentationScale: CGFloat {
        reduceMotion || windowPresented ? 1 : 0.98
    }
}
