//
//  SkillEditorPane.swift
//  Sage
//
//  Native Markdown editor for an existing SKILL.md.
//

import AppKit
import MarkdownEngine
import SwiftUI

struct SkillEditorPane: View {
    enum Mode: String, CaseIterable {
        case write = "Write"
        case preview = "Preview"
    }

    private struct Snapshot: Equatable {
        var description = ""
        var body = ""
        var license = ""
        var compatibility = ""
        var allowedTools = ""
        var metadata = ""
    }

    let skill: SkillRecord
    let reloadSkills: () async -> Void
    let onDirtyChanged: (Bool) -> Void

    @Environment(\.sageTypography) private var type
    @State private var mode: Mode = .write
    @State private var draft = Snapshot()
    @State private var saved = Snapshot()
    @State private var modificationDate: Date?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var detailsExpanded = false
}

extension SkillEditorPane {
    private var isDirty: Bool { draft != saved }
    private var canSave: Bool {
        isDirty
            && !isSaving
            && !draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && metadataDictionary != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider().opacity(SageDesign.Chrome.dividerOpacity)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                metadataFields
                Divider().opacity(SageDesign.Chrome.dividerOpacity)
                bodyEditor
            }
        }
        .task(id: skill.path) {
            await load()
        }
        .onChange(of: isDirty) { _, dirty in
            onDirtyChanged(dirty)
        }
        .alert("Couldn’t Save Skill", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: SageDesign.Spacing.small) {
            Picker("Editor Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Spacer()

            if isDirty {
                Text("Edited")
                    .font(.system(size: type.micro))
                    .foregroundStyle(.secondary)
            }

            Button("Revert") {
                draft = saved
            }
            .disabled(!isDirty || isSaving)

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!canSave)
        }
        .controlSize(.small)
        .padding(.horizontal, SageDesign.Spacing.extraLarge)
        .padding(.vertical, SageDesign.Spacing.small)
    }

    private var metadataFields: some View {
        VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
            TextField("Description", text: $draft.description, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            DisclosureGroup("Details", isExpanded: $detailsExpanded) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    detailRow("License", text: $draft.license, prompt: "Optional")
                    detailRow("Compatibility", text: $draft.compatibility, prompt: "Optional")
                    detailRow("Allowed tools", text: $draft.allowedTools, prompt: "Space-separated tool names")

                    GridRow {
                        Text("Metadata")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("One key=value pair per line", text: $draft.metadata, axis: .vertical)
                                .lineLimit(2...5)
                            if !draft.metadata.isEmpty, metadataDictionary == nil {
                                Text("Use one non-empty key=value pair per line.")
                                    .font(.system(size: type.micro))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, SageDesign.Spacing.small)
            }
            .font(.system(size: type.caption))
        }
        .padding(.horizontal, SageDesign.Spacing.extraLarge)
        .padding(.vertical, SageDesign.Spacing.medium)
    }

    private func detailRow(_ label: String, text: Binding<String>, prompt: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
        }
    }

    @ViewBuilder private var bodyEditor: some View {
        switch mode {
        case .write:
            NativeTextViewWrapper(
                text: $draft.body,
                configuration: editorConfiguration,
                fontName: "SF Pro",
                fontSize: type.body,
                documentId: skill.path,
                placeholder: NSAttributedString(
                    string: "Write instructions in Markdown…",
                    attributes: [.foregroundColor: NSColor.placeholderTextColor]
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .preview:
            ScrollView {
                if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No preview available.")
                        .font(.system(size: type.caption))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownContentView(
                        markdown: draft.body,
                        collapsible: false,
                        syntaxHighlighting: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
            }
            .padding(.horizontal, SageDesign.Spacing.extraLarge)
            .padding(.vertical, SageDesign.Spacing.large)
        }
    }

    private var editorConfiguration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.textInsets = TextInsets(
            horizontal: SageDesign.Spacing.extraLarge,
            vertical: SageDesign.Spacing.large
        )
        configuration.spellChecking = SpellCheckingPolicy(
            continuousSpellChecking: true,
            grammarChecking: true,
            automaticSpellingCorrection: false
        )
        return configuration
    }

    private var metadataDictionary: [String: String]? {
        var result: [String: String] = [:]
        for rawLine in draft.metadata.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let separator = line.firstIndex(of: "=") else { return nil }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            result[key] = value
        }
        return result
    }
}

private extension SkillEditorPane {
    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let record = skill
        let loaded = await Task.detached(priority: .utility) {
            let text = (try? String(contentsOfFile: record.path, encoding: .utf8)) ?? ""
            let date = try? URL(fileURLWithPath: record.path)
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            return (SkillMarkdown.stripFrontmatter(text), date)
        }.value
        let metadata = (skill.metadata ?? [:])
            .keys
            .sorted()
            .compactMap { key in skill.metadata?[key].map { "\(key)=\($0)" } }
            .joined(separator: "\n")
        let snapshot = Snapshot(
            description: skill.description,
            body: loaded.0,
            license: skill.license ?? "",
            compatibility: skill.compatibility ?? "",
            allowedTools: skill.allowedTools ?? "",
            metadata: metadata
        )
        draft = snapshot
        saved = snapshot
        modificationDate = loaded.1
        onDirtyChanged(false)
    }

    @MainActor
    private func save() async {
        guard canSave, let metadataDictionary else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await SkillWriter.updateSkill(
                existingRecord: skill,
                update: SkillWriter.Update(
                    description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: draft.body,
                    license: draft.license,
                    compatibility: draft.compatibility,
                    allowedTools: draft.allowedTools,
                    metadata: metadataDictionary
                ),
                expectedModificationDate: modificationDate
            )
            modificationDate = try? URL(fileURLWithPath: skill.path)
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            saved = draft
            onDirtyChanged(false)
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
