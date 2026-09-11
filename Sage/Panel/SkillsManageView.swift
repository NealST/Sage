//
//  SkillsManageView.swift
//  Sage
//
//  Settings-style skills browser: quiet source list + readable preview,
//  aligned with Apple Settings / Notes master–detail craft.
//

import SwiftUI

/// Shared between the SwiftUI editor and the window controller so the red
/// close button / Cmd-W can veto close while edits are unsaved.
@MainActor
@Observable
final class SkillsEditSession {
    var isDirty = false
    var canSave = false
    /// Registered by the active editor pane.
    var saveAction: (() async -> Bool)?
    /// Bumped when the window tried to close while dirty.
    var closeRequestID: UUID?

    func reset() {
        isDirty = false
        canSave = false
        saveAction = nil
        closeRequestID = nil
    }
}

struct SkillsManageView: View {
    @Environment(AppState.self) var appState
    @Environment(\.sageTypography) var type

    /// Pinned when opened from Settings so mid-edit key-window changes don't swap catalogs.
    var pinnedSession: AgentSession?
    /// Optional close handler for window presentation (falls back to `dismiss` in sheets).
    var onDone: (() -> Void)?
    /// Dirty state shared with the owning window (close protection).
    var editSession = SkillsEditSession()

    var session: AgentSession { pinnedSession ?? appState.keySession }
    @Environment(\.dismiss) var dismiss
    @State var selectedPath: String?
    @State var skillPendingDelete: SkillRecord?
    @State var deleteError: String?
    @State var previewBody: String = ""
    @State var globalSkills: [SkillRecord] = []
    @State var projectSkills: [SkillRecord] = []
    @State var searchText = ""
    @State var pendingSelectedPath: String?
    @State var showDiscardAlert = false
    @State var closeAfterDiscard = false

    var projectName: String {
        session.agent.state.focusedProject?.name ?? "This Project"
    }

    var selectedSkill: SkillRecord? {
        guard let selectedPath else { return nil }
        return session.skillCatalog.skills.first { $0.path == selectedPath }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if session.skillCatalog.skills.isEmpty {
                ContentUnavailableView {
                    Label("No Skills", systemImage: SageDesign.Symbol.skills)
                } description: {
                    Text("Ask Sage in chat to save a skill, or drop a SKILL.md folder into the locations below.")
                } actions: {
                    Button {
                        SkillFinderActions.openSkillsFolder(
                            scope: session.agent.state.focusedProject != nil ? .project : .global,
                            projectRoot: session.skillCatalog.currentProjectRoot
                        )
                    } label: {
                        Label("Open Skills Folder", systemImage: "folder")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    skillList
                        .frame(width: sourceListWidth)

                    Divider().opacity(SageDesign.Chrome.dividerOpacity)

                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            footer
        }
        .frame(minWidth: 640, minHeight: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshSkillSections()
            selectDefaultIfNeeded()
        }
        .onChange(of: session.skillCatalog.skills) { _, _ in
            refreshSkillSections()
            selectDefaultIfNeeded()
        }
        .alert(
            "Delete “\(skillPendingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { skillPendingDelete != nil },
                set: { if !$0 { skillPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { skillPendingDelete = nil }
            Button("Move to Trash", role: .destructive) {
                confirmDelete()
            }
        } message: {
            Text("The skill folder will be moved to Trash. This cannot be undone from Sage.")
        }
        .alert("Couldn’t Delete Skill", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Unsaved Changes", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) {
                pendingSelectedPath = nil
                closeAfterDiscard = false
            }
            Button(closeAfterDiscard ? "Save & Close" : "Save & Switch") {
                Task { await saveAndContinue() }
            }
            .disabled(!editSession.canSave)
            Button("Discard Changes", role: .destructive) {
                discardAndContinue()
            }
        } message: {
            Text("Your edits to this skill have not been saved.")
        }
        .onChange(of: editSession.closeRequestID) { _, _ in
            guard editSession.isDirty else { return }
            closeAfterDiscard = true
            showDiscardAlert = true
        }
        .onAppear {
            Task {
                await appState.reloadSkillsAcrossSessions()
            }
        }
    }

    /// Sidebar width — scales with Dynamic Type alongside the list rows.
    @ScaledMetric(relativeTo: .body) private var sourceListWidth: CGFloat = 200

    // MARK: - Chrome

    var toolbar: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Spacer(minLength: 0)

            Menu {
                Button("Everywhere Folder") {
                    SkillFinderActions.openSkillsFolder(
                        scope: .global,
                        projectRoot: session.skillCatalog.currentProjectRoot
                    )
                }
                if session.agent.state.focusedProject != nil {
                    Button("“\(projectName)” Folder") {
                        SkillFinderActions.openSkillsFolder(
                            scope: .project,
                            projectRoot: session.skillCatalog.currentProjectRoot
                        )
                    }
                }
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task {
                    await appState.reloadSkillsAcrossSessions()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.small)
    }
}
