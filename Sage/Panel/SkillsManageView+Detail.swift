//
//  SkillsManageView+Detail.swift
//  Sage
//

import SwiftUI

extension SkillsManageView {
    // MARK: - Source list

    var skillList: some View {
        List(selection: skillSelectionBinding) {
            if !visibleGlobalSkills.isEmpty {
                Section("Everywhere") {
                    ForEach(visibleGlobalSkills) { skill in
                        skillRow(skill)
                    }
                }
            }

            if !visibleProjectSkills.isEmpty {
                Section(projectName) {
                    ForEach(visibleProjectSkills) { skill in
                        skillRow(skill)
                    }
                }
            }

            if isFiltering, visibleGlobalSkills.isEmpty, visibleProjectSkills.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .listStyle(.sidebar)
        .sageScrollEdgeGlass()
        .environment(\.defaultMinListRowHeight, 28)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Search skills"
        )
    }

    var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var visibleGlobalSkills: [SkillRecord] {
        guard isFiltering else { return globalSkills }
        return globalSkills.filter { matchesSearch($0) }
    }

    var visibleProjectSkills: [SkillRecord] {
        guard isFiltering else { return projectSkills }
        return projectSkills.filter { matchesSearch($0) }
    }

    func matchesSearch(_ skill: SkillRecord) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return skill.name.localizedCaseInsensitiveContains(query)
            || skill.description.localizedCaseInsensitiveContains(query)
    }

    @ViewBuilder
    func skillRow(_ skill: SkillRecord) -> some View {
        HStack(spacing: 8) {
            Text(skill.name)
                .sageFont(type.body, weight: .medium)
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
            .controlSize(.small)
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
                            .sageFont(type.title, weight: .semibold)
                            .lineLimit(1)
                        Text(locationCaption(for: selected))
                            .sageMicro(type.micro)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Button("Show in Finder") {
                        SkillFinderActions.revealSkill(selected)
                    }
                    .controlSize(.small)
                    .help("Reveal this skill’s SKILL.md in Finder")
                }
                .padding(.horizontal, SageDesign.Spacing.extraLarge)
                .padding(.vertical, SageDesign.Spacing.medium)

                SkillEditorPane(
                    skill: selected,
                    reloadSkills: {
                        await appState.reloadSkillsAcrossSessions()
                    },
                    editSession: editSession
                )
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

    var footer: some View {
        HStack {
            Text(footerSummary)
                .sageMicro(type.micro)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done", action: performDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, SageDesign.Spacing.large)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    func performDone() {
        guard editSession.isDirty else {
            closeWindow()
            return
        }
        closeAfterDiscard = true
        showDiscardAlert = true
    }

    /// Alert choice: persist the pending edits, then continue with the
    /// deferred close or selection switch. A failed save keeps the window
    /// open — the pane surfaces the error itself.
    func saveAndContinue() async {
        guard await editSession.saveAction?() == true else { return }
        continueAfterResolvedEdit()
    }

    /// Alert choice: drop the pending edits and continue.
    func discardAndContinue() {
        editSession.isDirty = false
        continueAfterResolvedEdit()
    }

    private func continueAfterResolvedEdit() {
        if closeAfterDiscard {
            closeAfterDiscard = false
            closeWindow()
        } else {
            selectedPath = pendingSelectedPath
        }
        pendingSelectedPath = nil
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
                guard editSession.isDirty else {
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
