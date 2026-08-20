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

    private var session: AgentSession { pinnedSession ?? appState.keySession }
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String?
    @State private var skillPendingDelete: SkillRecord?
    @State private var deleteError: String?
    @State private var previewBody: String = ""
    @State private var globalSkills: [SkillRecord] = []
    @State private var projectSkills: [SkillRecord] = []
    /// Frontmatter description starts collapsed when long so the body stays visible.
    @State private var descriptionExpanded = false

    private var projectName: String {
        session.agent.state.focusedProject?.name ?? "This Project"
    }

    private var selectedSkill: SkillRecord? {
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

    private static let sourceListWidth: CGFloat = 200

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: SageDesign.Spacing.sm) {
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
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.sm)
    }

    // MARK: - Source list

    private var skillList: some View {
        List(selection: $selectedPath) {
            if !globalSkills.isEmpty {
                Section("Everywhere") {
                    ForEach(globalSkills) { skill in
                        skillRow(skill)
                    }
                }
            }

            if !projectSkills.isEmpty {
                Section(projectName) {
                    ForEach(projectSkills) { skill in
                        skillRow(skill)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.defaultMinListRowHeight, 28)
    }

    @ViewBuilder
    private func skillRow(_ skill: SkillRecord) -> some View {
        HStack(spacing: 8) {
            Text(skill.name)
                .font(.system(size: type.body, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { skill.enabled },
                    set: { enabled in
                        session.skillCatalog.setSkillEnabled(skill, enabled: enabled)
                        Task { await appState.syncSkillEnablement(from: session) }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .tag(skill.path)
        .help(skill.description)
        .contextMenu {
            Button("Show in Finder") {
                SkillFinderActions.revealSkill(skill)
            }
            Divider()
            Button("Move to Trash…", role: .destructive) {
                skillPendingDelete = skill
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let selected = selectedSkill {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: SageDesign.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.name)
                            .font(.system(size: type.title, weight: .semibold))
                            .lineLimit(1)
                        Text(locationCaption(for: selected))
                            .font(.system(size: type.micro))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Button("Show in Finder") {
                        SkillFinderActions.revealSkill(selected)
                    }
                    .controlSize(.small)

                    Button("Delete…", role: .destructive) {
                        skillPendingDelete = selected
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, SageDesign.Spacing.xl)
                .padding(.vertical, SageDesign.Spacing.md)

                if !selected.description.isEmpty {
                    skillDescriptionSection(selected.description)
                }

                Divider().opacity(SageDesign.Chrome.dividerOpacity)

                ScrollView {
                    Group {
                        if previewBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("No preview available.")
                                .font(.system(size: type.caption))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MarkdownContentView(
                                markdown: previewBody,
                                collapsible: false,
                                syntaxHighlighting: false
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, SageDesign.Spacing.xl)
                    .padding(.vertical, SageDesign.Spacing.lg)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            .task(id: selected.path) {
                descriptionExpanded = false
                previewBody = await SkillRegistry.shared.readBody(for: selected)
            }
        } else {
            ContentUnavailableView(
                "Select a Skill",
                systemImage: "doc.text",
                description: Text("Choose a skill to preview its contents.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Collapsed frontmatter description — keeps the markdown body on screen.
    private func skillDescriptionSection(_ description: String) -> some View {
        let collapsible = Self.descriptionNeedsCollapse(description)

        return VStack(alignment: .leading, spacing: 6) {
            Text(description)
                .font(.system(size: type.caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(collapsible && !descriptionExpanded ? Self.collapsedDescriptionLineLimit : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .animation(SageDesign.Motion.expandAnimation, value: descriptionExpanded)

            if collapsible {
                Button {
                    withAnimation(SageDesign.Motion.expandAnimation) {
                        descriptionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(descriptionExpanded ? "Show less" : "Show more")
                            .font(.system(size: type.micro, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(descriptionExpanded ? 180 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(descriptionExpanded ? "Collapse description" : "Expand description")
            }
        }
        .padding(.horizontal, SageDesign.Spacing.xl)
        .padding(.bottom, SageDesign.Spacing.md)
    }

    private static let collapsedDescriptionLineLimit = 3

    private static func descriptionNeedsCollapse(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return text.count > 160 || lines > collapsedDescriptionLineLimit
    }

    private var footer: some View {
        HStack {
            Text(footerSummary)
                .font(.system(size: type.micro))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done", action: performDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.md)
    }

    private func performDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private var footerSummary: String {
        let globalCount = globalSkills.count
        let projectCount = projectSkills.count
        if session.agent.state.focusedProject != nil {
            return "\(globalCount) everywhere · \(projectCount) in \(projectName)"
        }
        return "\(globalCount) skill\(globalCount == 1 ? "" : "s")"
    }

    private func locationCaption(for skill: SkillRecord) -> String {
        let location: String
        switch skill.scope {
        case .global:
            location = "Everywhere — available in every workspace"

        case .project:
            location = "This Project — only used in “\(projectName)”"
        }
        if skill.isAutoGenerated {
            return "\(location) · Auto-generated"
        }
        return location
    }

    private func refreshSkillSections() {
        let skills = session.skillCatalog.skills
        globalSkills = skills
            .filter { $0.scope == .global }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        projectSkills = skills
            .filter { $0.scope == .project }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func selectDefaultIfNeeded() {
        let paths = Set((globalSkills + projectSkills).map(\.path))
        if let selectedPath, paths.contains(selectedPath) { return }
        selectedPath = globalSkills.first?.path ?? projectSkills.first?.path
    }

    private func confirmDelete() {
        guard let skill = skillPendingDelete else { return }
        skillPendingDelete = nil
        Task {
            do {
                try await session.skillCatalog.deleteSkill(skill)
                if selectedPath == skill.path {
                    selectedPath = nil
                }
                await appState.reloadSkillsAcrossSessions()
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }
}
