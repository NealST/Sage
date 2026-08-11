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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String?
    @State private var skillPendingDelete: SkillRecord?
    @State private var deleteError: String?

    private var projectName: String {
        appState.agent.focusedProject?.name ?? "This Project"
    }

    private var globalSkills: [SkillRecord] {
        appState.capabilities.skills.filter { $0.scope == .global }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var projectSkills: [SkillRecord] {
        appState.capabilities.skills.filter { $0.scope == .project }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedSkill: SkillRecord? {
        guard let selectedPath else { return nil }
        return appState.capabilities.skills.first { $0.path == selectedPath }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            if appState.capabilities.skills.isEmpty {
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
                await appState.capabilities.reloadSkills(
                    projectRoot: appState.agent.focusedProject?.rootURL
                )
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
                    appState.capabilities.openSkillsFolder(scope: .global)
                }
                if appState.agent.focusedProject != nil {
                    Button("“\(projectName)” Folder") {
                        appState.capabilities.openSkillsFolder(scope: .project)
                    }
                }
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                Task {
                    await appState.capabilities.reloadSkills(
                        projectRoot: appState.agent.focusedProject?.rootURL
                    )
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
                    set: { appState.capabilities.setSkillEnabled(skill.name, enabled: $0) }
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
                appState.capabilities.revealSkill(skill)
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
                        appState.capabilities.revealSkill(selected)
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
                    Text(SkillRegistry.readBody(for: selected))
                        .font(.system(size: SageDesign.Typography.captionSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(SageDesign.Spacing.lg)
                }
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
        if appState.agent.focusedProject != nil {
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

    private func confirmDelete() {
        guard let skill = skillPendingDelete else { return }
        skillPendingDelete = nil
        do {
            try appState.capabilities.deleteSkill(skill)
            if selectedPath == skill.path {
                selectedPath = nil
            }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
