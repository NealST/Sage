//
//  SkillsManageView.swift
//  Sage
//
//  Settings-style skills browser: quiet sections by location, enable toggles,
//  preview, Reveal in Finder, and delete — aligned with Apple Settings craft.
//

import SwiftUI

struct SkillsManageView: View {
    @Environment(AppState.self) private var appState

    /// Pinned when opened from Settings so mid-edit key-window changes don't swap catalogs.
    var pinnedSession: AgentSession? = nil

    private var session: AgentSession { pinnedSession ?? appState.keySession }
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String?
    @State private var skillPendingDelete: SkillRecord?
    @State private var deleteError: String?
    @State private var previewBody: String = ""
    @State private var globalSkills: [SkillRecord] = []
    @State private var projectSkills: [SkillRecord] = []

    private var projectName: String {
        session.agent.state.focusedProject?.name ?? "This Project"
    }

    private var selectedSkill: SkillRecord? {
        guard let selectedPath else { return nil }
        return session.skillCatalog.skills.first { $0.path == selectedPath }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            if session.skillCatalog.skills.isEmpty {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: SageDesign.Symbol.skills,
                    description: Text("Skills you save appear here, grouped by location.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    skillList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                    detailPane
                        .frame(minWidth: 240)
                }
            }

            Divider().opacity(SageDesign.Chrome.dividerOpacity)
            footer
        }
        .frame(width: 640, height: 520)
        .onAppear { refreshSkillSections() }
        .onChange(of: session.skillCatalog.skills) { _, _ in
            refreshSkillSections()
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

    private var header: some View {
        HStack(spacing: SageDesign.Spacing.sm) {
            Text("Skills")
                .font(.headline)

            Spacer()

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
        .padding(.vertical, SageDesign.Spacing.md)
    }

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
    }

    @ViewBuilder
    private func skillRow(_ skill: SkillRecord) -> some View {
        HStack(alignment: .center, spacing: SageDesign.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: SageDesign.Typography.bodySize, weight: .medium))
                    .lineLimit(1)
                Text(skill.description)
                    .font(.system(size: SageDesign.Typography.microSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if skill.isAutoGenerated {
                    Text("Auto-generated")
                        .font(.system(size: SageDesign.Typography.microSize))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

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
        .padding(.vertical, 2)
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

    @ViewBuilder
    private var detailPane: some View {
        if let selected = selectedSkill {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: SageDesign.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.name)
                            .font(.system(size: SageDesign.Typography.titleSize, weight: .semibold))
                        Text(locationCaption(for: selected))
                            .font(.system(size: SageDesign.Typography.microSize))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Show in Finder") {
                        SkillFinderActions.revealSkill(selected)
                    }
                    .controlSize(.small)

                    Button("Delete…", role: .destructive) {
                        skillPendingDelete = selected
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, SageDesign.Spacing.lg)
                .padding(.vertical, SageDesign.Spacing.md)

                Divider().opacity(SageDesign.Chrome.dividerOpacity)

                ScrollView {
                    Text(previewBody)
                        .font(.system(size: SageDesign.Typography.captionSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(SageDesign.Spacing.lg)
                }
            }
            .task(id: selected.path) {
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

    private var footer: some View {
        HStack {
            Text(footerSummary)
                .font(.system(size: SageDesign.Typography.microSize))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, SageDesign.Spacing.lg)
        .padding(.vertical, SageDesign.Spacing.md)
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
