//
//  SettingsView.swift
//  Sage
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: ModelSettings
    var onDone: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Base URL", text: $settings.baseURL)
                    TextField("Model", text: $settings.model)
                    SecureField("API Key", text: $settings.apiKey)
                } header: {
                    Text("Model Provider")
                } footer: {
                    Text("OpenAI-compatible Chat Completions API. Example: https://api.openai.com/v1")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.top, SageDesign.Spacing.sm)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    onDone?()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, SageDesign.Spacing.lg)
            .padding(.vertical, SageDesign.Spacing.md)
        }
        .frame(width: 460, height: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    SettingsView(settings: .shared)
}
