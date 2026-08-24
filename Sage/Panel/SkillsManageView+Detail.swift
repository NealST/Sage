//
//  SkillsManageView+Detail.swift
//  Sage
//

import SwiftUI

extension SkillsManageView {
    // MARK: - Source list

    var skillList: some View {
        List(selection: skillSelectionBinding) {
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
    func skillRow(_ skill: SkillRecord) -> some View {
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

    @ViewBuilder var detailPane: some View {
        if let selected = selectedSkill {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: SageDesign.Spacing.small) {
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
                .padding(.horizontal, SageDesign.Spacing.extraLarge)
                .padding(.vertical, SageDesign.Spacing.medium)

                Divider().opacity(SageDesign.Chrome.dividerOpacity)

                SkillEditorPane(
                    skill: selected,
                    reloadSkills: {
                        await appState.reloadSkillsAcrossSessions()
                    },
                    onDirtyChanged: { dirty in
                        editorDirty = dirty
                    }
                )
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
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
    func skillDescriptionSection(_ description: String) -> some View {
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
        .padding(.horizontal, SageDesign.Spacing.extraLarge)
        .padding(.bottom, SageDesign.Spacing.medium)
    }

    static let collapsedDescriptionLineLimit = 3

    static func descriptionNeedsCollapse(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return text.count > 160 || lines > collapsedDescriptionLineLimit
    }

    var footer: some View {
        HStack {
            Text(footerSummary)
                .font(.system(size: type.micro))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done", action: performDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    func performDone() {
        guard !editorDirty else {
            closeAfterDiscard = true
            showDiscardAlert = true
            return
        }
        closeWindow()
    }

    func closeWindow() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    var footerSummary: String {
        let globalCount = globalSkills.count
        let projectCount = projectSkills.count
        if session.agent.state.focusedProject != nil {
            return "\(globalCount) everywhere · \(projectCount) in \(projectName)"
        }
        return "\(globalCount) skill\(globalCount == 1 ? "" : "s")"
    }

    func locationCaption(for skill: SkillRecord) -> String {
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

    func refreshSkillSections() {
        let skills = session.skillCatalog.skills
        globalSkills = skills
            .filter { $0.scope == .global }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        projectSkills = skills
            .filter { $0.scope == .project }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func selectDefaultIfNeeded() {
        let paths = Set((globalSkills + projectSkills).map(\.path))
        if let selectedPath, paths.contains(selectedPath) { return }
        selectedPath = globalSkills.first?.path ?? projectSkills.first?.path
    }

    var skillSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedPath },
            set: { requestedPath in
                guard requestedPath != selectedPath else { return }
                guard editorDirty else {
                    selectedPath = requestedPath
                    return
                }
                pendingSelectedPath = requestedPath
                closeAfterDiscard = false
                showDiscardAlert = true
            }
        )
    }

    func confirmDelete() {
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
