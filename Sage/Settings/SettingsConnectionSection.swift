//
//  SettingsConnectionSection.swift
//  Sage
//

import SwiftUI

enum SettingsConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

struct SettingsConnectionSection: View {
    @Bindable var settings: ModelSettings
    var testState: SettingsConnectionTestState
    var onFieldChange: () -> Void

    var body: some View {
        Section {
            connectionField(
                "Base URL",
                text: $settings.baseURL,
                prompt: "https://api.openai.com/v1",
                error: baseURLValidationError
            ) {
                onFieldChange()
            }

            connectionField(
                "Model",
                text: $settings.model,
                prompt: "gpt-4.1-mini",
                error: modelValidationError
            ) {
                onFieldChange()
            }

            connectionField("Plan model", text: $settings.planModel, prompt: "same as Model")
            connectionField("Execute model", text: $settings.executeModel, prompt: "same as Model")
            connectionField("Review model", text: $settings.reviewModel, prompt: "same as Model")

            LabeledContent("API Key") {
                VStack(alignment: .trailing, spacing: 4) {
                    SecureField("sk-…", text: $settings.apiKey)
                        .onChange(of: settings.apiKey) { _, _ in onFieldChange() }
                    if let apiKeyValidationError {
                        Text(apiKeyValidationError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } footer: {
            statusRow
        }
    }

    static func canTest(_ settings: ModelSettings) -> Bool {
        baseURLError(in: settings) == nil
            && modelError(in: settings) == nil
            && apiKeyError(in: settings) == nil
    }

    @ViewBuilder
    private func connectionField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        error: String? = nil,
        onChange: (() -> Void)? = nil
    ) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(prompt, text: text)
                    .onChange(of: text.wrappedValue) { _, _ in onChange?() }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var statusRow: some View {
        Group {
            if let persistenceError = settings.apiKeyPersistenceError {
                Text(persistenceError)
            } else {
                switch testState {
                case .idle:
                    Text("Stored in Keychain · saves automatically")

                case .testing:
                    Text("Testing connection…")

                case .success:
                    Text("Connection succeeded")

                case .failure(let message):
                    Text(message)
                }
            }
        }
        .accessibilityLabel(statusAccessibilityLabel)
    }

    private var statusAccessibilityLabel: String {
        if let persistenceError = settings.apiKeyPersistenceError {
            return persistenceError
        }
        switch testState {
        case .idle: return "API key stored in Keychain. Changes save automatically."
        case .testing: return "Testing connection"
        case .success: return "Connection succeeded"
        case .failure(let message): return message
        }
    }

    private var baseURLValidationError: String? { Self.baseURLError(in: settings) }

    private var modelValidationError: String? { Self.modelError(in: settings) }

    private var apiKeyValidationError: String? { Self.apiKeyError(in: settings) }

    static func baseURLError(in settings: ModelSettings) -> String? {
        let trimmed = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Base URL is required" }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return "Enter a valid http(s) URL"
        }
        return nil
    }

    static func modelError(in settings: ModelSettings) -> String? {
        settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Model is required"
            : nil
    }

    static func apiKeyError(in settings: ModelSettings) -> String? {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API key is required"
        }
        return settings.apiKeyPersistenceError
    }
}
