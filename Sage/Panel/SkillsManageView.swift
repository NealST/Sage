//
//  SkillsManageView.swift
//  Sage
//
//  Settings-style skills browser: quiet source list + readable preview,
//  aligned with Apple Settings / Notes master–detail craft.
//

import SwiftUI

struct SkillsManageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sageTypography) private var type

    /// Pinned when opened from Settings so mid-edit key-window changes don't swap catalogs.
    var pinnedSession: AgentSession?
    /// Optional close handler for window presentation (falls back to `dismiss` in sheets).
    var onDone: (() -> Void)?

    var session: AgentSession { pinnedSession ?? appState.keySession }
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String?
    @State private var skillPendingDelete: SkillRecord?
    @State private var deleteError: String?
    @State private var previewBody: String = ""
    @State private var globalSkills: [SkillRecord] = []
    @State private var projectSkills: [SkillRecord] = []
    /// Frontmatter description starts collapsed when long so the body stays visible.
    @State private var descriptionExpanded = false

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
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            if session.skillCatalog.skills.isEmpty {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: SageDesign.Symbol.skills,
                    description: Text("Skills you save appear here, grouped by location.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    skillList
                        .frame(width: Self.sourceListWidth)

                    Divider().opacity(SageDesign.Chrome.dividerOpacity)

                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider().opacity(SageDesign.Chrome.dividerOpacity)
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
        .onAppear {
            Task {
                await appState.reloadSkillsAcrossSessions()
            }
        }
    }

    static let sourceListWidth: CGFloat = 200

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

            Button {
                Task {
                    await appState.reloadSkillsAcrossSessions()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.small)
    }
}
