//
//  WorkspaceChromeView.swift
//  Sage
//

import AppKit
import SwiftUI

/// Unified titlebar: identity · document · actions / view mode.
/// One row with the traffic lights, not a second stacked toolbar.
struct WorkspaceChromeView: View {
    @Environment(AppState.self) var appState
    @Environment(AgentSession.self) var session
    @Environment(AccessibilitySettings.self) var accessibility
    /// Shared with the +Identity extension file.
    @Environment(\.sageTypography) var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var gitBranch: String?
    /// Prefetched in the background — building the menu must not shell out.
    @Binding var gitBranches: [String]
    @Binding var branchSwitchError: String?
    @Binding var projectTab: ProjectWorkspaceTab
    /// General window: full task-history browser sheet.
    @State private var isBrowsingTasks = false
    /// Seconds in the current working stretch — feeds the badge's elapsed label.
    @State private var workingElapsedSeconds = 0
    /// Horizontal container inset on the titlebar band — subtracted from the
    /// traffic-light clearance so the identity cluster lands on window
    /// coordinates regardless of how the system insets the band.
    @State private var safeLeadingInset: CGFloat = 0
    /// Chrome control widths scale with Dynamic Type — hardcoded frames
    /// truncate large type (used by the +Identity extension).
    @ScaledMetric(relativeTo: .caption) var tabPickerMinWidth: CGFloat = 200
    @ScaledMetric(relativeTo: .caption) var tabPickerIdealWidth: CGFloat = 220
    @ScaledMetric(relativeTo: .caption) var tabPickerMaxWidth: CGFloat = 240
    @ScaledMetric(relativeTo: .caption) var recentsMenuMaxWidth: CGFloat = 200

    var focused: ProjectRecord? { session.agent.state.focusedProject }
    var isProject: Bool { !session.isGeneral }

    var body: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            identityCluster
                .sageFont(type.caption, weight: .medium)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)

            if showsDocumentCluster {
                chromeSeparator
                documentCluster
                    .sageFont(type.caption, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: SageDesign.Spacing.medium)

            trailingCluster
                .symbolRenderingMode(.hierarchical)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One row on the traffic-light centerline: the identity cluster
        // clears the lights (window x ≈ 88); the trailing cluster keeps the
        // 16pt page gutter the composer and transcript use.
        .padding(.leading, leadingChromeInset)
        .padding(.trailing, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.small)
        .frame(minHeight: SageDesign.Panel.titlebarContentHeight)
        // The band is SwiftUI chrome over the system toolbar area, so empty
        // stretches of the row must still act like a titlebar: drag to move
        // the window, double-click to zoom. An opaque AppKit layer behind
        // the controls paints the window background and forwards mouse-down
        // the way a real titlebar would.
        .background { TitlebarDragArea() }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.leading } action: { newValue in
            safeLeadingInset = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .sageBrowseTaskHistory)) { note in
            // Sheet lives in the General window only; project windows route
            // the command to their History tab instead.
            guard !isProject,
                  note.object as? AgentSession.Kind == session.kind
            else { return }
            isBrowsingTasks = true
        }
    }

    /// Window x where chrome content begins — past the traffic lights (they
    /// end around x=80 on the unified toolbar band) with breathing room. The
    /// row already carries the window's horizontal safe-area inset, so it is
    /// subtracted to keep this a window-coordinate value.
    private var leadingChromeInset: CGFloat {
        max(
            SageDesign.Panel.titlebarLeadingInset - safeLeadingInset,
            SageDesign.Spacing.large
        )
    }

    // MARK: - Zones

    @ViewBuilder var identityCluster: some View {
        if isProject {
            projectIdentity
        } else {
            generalIdentity
        }
    }

    var generalIdentity: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Button(action: openProject) {
                Label("Open Project", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .sageGlassButton()
            .sageHelp("Open Project")
            .accessibilityLabel("Open Project")

            Button(action: createProject) {
                Label("New Project", systemImage: "folder.badge.plus")
                    .labelStyle(.iconOnly)
            }
            .sageGlassButton()
            .sageHelp("New Project")
            .accessibilityLabel("New Project")

            if !session.agent.state.recentProjects.isEmpty {
                Menu {
                    ForEach(session.agent.state.recentProjects) { project in
                        Button {
                            Task { await appState.switchToProject(id: project.id) }
                        } label: {
                            Text("\(project.name) · \(ProjectPanelActions.displayPath(project.rootPath))")
                        }
                    }
                } label: {
                    // `clock.arrow.circlepath`, not `clock` — Browse Tasks
                    // already owns the plain clock on the trailing side.
                    Label("Recent Projects", systemImage: "clock.arrow.circlepath")
                        .labelStyle(.iconOnly)
                }
                .sageGlassButton()
                .sageHelp("Recent Projects")
                .accessibilityLabel("Recent Projects")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var projectIdentity: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.labelGap) {
            if let focused {
                projectNameButton(focused)
            } else {
                Text("Opening…")
            }

            if gitBranch != nil {
                branchMenu
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder var documentCluster: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            if isWorking {
                workingBadge
            }

            if let title = session.agent.state.threadTitle,
               session.agent.state.activeTask?.events.isEmpty == false {
                recentTasksControl(currentTitle: title)
            } else if hasOtherRecentTasks {
                recentTasksControl(currentTitle: nil)
            }
        }
        .layoutPriority(0)
    }

    /// Long turns would otherwise read as a frozen window — this answers
    /// "is this window doing anything" from across the room. After the grace
    /// window the elapsed count appears (same formatter as the transcript's
    /// thinking label), so a stuck turn is distinguishable from a fresh one.
    private var workingBadge: some View {
        Label(workingTitle, systemImage: "circle.dotted")
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: !reduceMotion
            )
            .padding(.horizontal, SageDesign.Spacing.compactChipHorizontal)
            .padding(.vertical, SageDesign.Spacing.compactChipVertical)
            .sageGlassChip()
            .accessibilityLabel("Sage is working")
            .task(id: isWorking) {
                guard isWorking else { return }
                workingElapsedSeconds = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    workingElapsedSeconds += 1
                }
            }
    }

    private var workingTitle: String {
        SageDesign.Elapsed.label(workingElapsedSeconds).map { "Working \($0)" }
            ?? "Working"
    }

    private var isWorking: Bool {
        switch session.agent.state.phase {
        case .thinking, .executing: return true
        case .idle, .awaitingConfirmation, .completed, .failed: return false
        }
    }

    @ViewBuilder var trailingCluster: some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
            if session.agent.canStartFresh {
                Button {
                    session.resetComposer()
                    Task { await session.agent.startFresh() }
                } label: {
                    Label("Start Fresh", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .sageGlassButton()
                .disabled(!session.agent.canStartFresh)
                .sageHelp("Start Fresh")
            }

            if !isProject, hasTaskHistory {
                Button {
                    isBrowsingTasks = true
                } label: {
                    Label("Browse Tasks", systemImage: "clock")
                        .labelStyle(.iconOnly)
                }
                .sageGlassButton()
                .sageHelp("Browse Tasks")
                .sheet(isPresented: $isBrowsingTasks) {
                    TaskHistorySheet(
                        repository: appState.taskRepository,
                        projectID: nil
                    )
                }
            }

            if isProject {
                projectTabPicker
            }
        }
        .layoutPriority(1)
    }

    private var hasTaskHistory: Bool {
        session.agent.state.recentSummaries.contains { !$0.isScheduled }
    }

    var showsDocumentCluster: Bool {
        if isWorking { return true }
        if session.agent.state.threadTitle != nil,
           session.agent.state.activeTask?.events.isEmpty == false {
            return true
        }
        return hasOtherRecentTasks
    }

    var chromeSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(SageDesign.Chrome.dividerOpacity))
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }
}

/// Empty stretches of the titlebar band must behave like a real titlebar.
/// The chrome row is SwiftUI content over the system toolbar area, so an
/// opaque AppKit layer behind the controls forwards mouse-downs as a
/// window drag (and double-click as zoom) the way the system titlebar does.
/// The fill is `windowBackgroundColor` so the band matches the window and
/// conversation instead of glass-blending through the transparent titlebar.
private struct TitlebarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.refreshFill()
    }

    final class DragView: NSView {
        override var isOpaque: Bool { true }
        override var wantsUpdateLayer: Bool { true }
        override var acceptsFirstResponder: Bool { false }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
        }

        override func updateLayer() {
            refreshFill()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            refreshFill()
        }

        func refreshFill() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.windowBackgroundColor
                    .withAlphaComponent(1)
                    .cgColor
            }
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}
