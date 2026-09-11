//
//  SkillSecretsEditor.swift
//  Sage
//

import SwiftUI

struct SkillSecretsEditor: View {
    let skill: SkillRecord

    @Environment(\.sageTypography) private var type
    /// Secret-name column width — scales with Dynamic Type alongside the names.
    @ScaledMetric(relativeTo: .caption) private var nameLabelWidth: CGFloat = 150
    @State private var drafts: [String: String] = [:]
    @State private var storedNames: Set<String> = []
    @State private var errorMessage: String?
    /// Secret pending removal — the confirm step stands between the button
    /// and a Keychain delete that has no undo.
    @State private var removalPending: String?

    var body: some View {
        if !skill.requiredSecretNames.isEmpty {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                Text("Skill secrets")
                    .sageFont(type.caption, weight: .medium)
                Text("Stored in Keychain and injected only after secret-use authorization.")
                    .sageMicro(type.micro)
                    .foregroundStyle(.secondary)

                ForEach(skill.requiredSecretNames.sorted(), id: \.self) { name in
                    HStack(spacing: SageDesign.Spacing.small) {
                        Text(name)
                            .sageMicro(type.micro, design: .monospaced)
                            .frame(width: nameLabelWidth, alignment: .leading)
                        SecureField(
                            storedNames.contains(name) ? "Stored — enter to replace" : "Secret value",
                            text: binding(for: name)
                        )
                        Button("Save") {
                            save(name)
                        }
                        .disabled(drafts[name, default: ""].isEmpty)
                        if storedNames.contains(name) {
                            Button("Remove", role: .destructive) {
                                removalPending = name
                            }
                        }
                    }
                    .controlSize(.small)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .sageMicro(type.micro)
                        .foregroundStyle(SageDesign.Palette.danger)
                }
            }
            .confirmationDialog(
                "Remove this secret?",
                isPresented: Binding(
                    get: { removalPending != nil },
                    set: { if !$0 { removalPending = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    guard let name = removalPending else { return }
                    removalPending = nil
                    SkillSecretStore.removeSecret(name, for: skill)
                    storedNames.remove(name)
                    drafts[name] = ""
                }
                Button("Cancel", role: .cancel) {
                    removalPending = nil
                }
            } message: {
                Text(
                    removalPending.map { name in
                        "“\(name)” will be deleted from your Keychain. The skill will ask you to enter it again next time it needs it."
                    } ?? ""
                )
            }
            .task(id: skill.id + "\n" + skill.requiredSecretNames.sorted().joined(separator: "\n")) {
                refresh()
            }
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { drafts[name, default: ""] },
            set: { drafts[name] = $0 }
        )
    }

    private func save(_ name: String) {
        do {
            try SkillSecretStore.setSecret(drafts[name, default: ""], variable: name, for: skill)
            drafts[name] = ""
            storedNames.insert(name)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        storedNames = Set(skill.requiredSecretNames.filter { name in
            SkillSecretStore.hasStoredSecret(name, for: skill)
        })
        drafts = [:]
        errorMessage = nil
    }
}
