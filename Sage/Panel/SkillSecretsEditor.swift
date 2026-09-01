//
//  SkillSecretsEditor.swift
//  Sage
//

import SwiftUI

struct SkillSecretsEditor: View {
    let skill: SkillRecord

    @Environment(\.sageTypography) private var type
    @State private var drafts: [String: String] = [:]
    @State private var storedNames: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        if !skill.requiredSecretNames.isEmpty {
            VStack(alignment: .leading, spacing: SageDesign.Spacing.small) {
                Text("Skill secrets")
                    .font(.system(size: type.caption, weight: .medium))
                Text("Stored in Keychain and injected only after secret-use authorization.")
                    .font(.system(size: type.micro))
                    .foregroundStyle(.secondary)

                ForEach(skill.requiredSecretNames.sorted(), id: \.self) { name in
                    HStack(spacing: SageDesign.Spacing.small) {
                        Text(name)
                            .font(.system(size: type.micro, design: .monospaced))
                            .frame(width: 150, alignment: .leading)
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
                                SkillSecretStore.removeSecret(name, for: skill)
                                storedNames.remove(name)
                                drafts[name] = ""
                            }
                        }
                    }
                    .controlSize(.small)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: type.micro))
                        .foregroundStyle(.red)
                }
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
