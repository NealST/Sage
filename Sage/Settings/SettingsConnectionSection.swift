//
//  SettingsConnectionSection.swift
//  Sage
//

import SwiftUI

struct SettingsConnectionSection: View {
    @Bindable var settings: ModelSettings
    var testState: SettingsConnectionTestState
    var onFieldChange: () -> Void

    var body: some View {
        SettingsFormChrome.section("Connection") {
            VStack(spacing: 0) {
                SettingsFormChrome.field(
                    title: "Base URL",
                    error: baseURLValidationError,
                    isFirst: true
                ) {
                    TextField("https://api.openai.com/v1", text: $settings.baseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                        .onChange(of: settings.baseURL) { _, _ in onFieldChange() }
                }

                SettingsFormChrome.divider

                SettingsFormChrome.field(
                    title: "Model",
                    error: modelValidationError
                ) {
                    TextField("gpt-4.1-mini", text: $settings.model)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                        .onChange(of: settings.model) { _, _ in onFieldChange() }
                }

                SettingsFormChrome.divider

                SettingsFormChrome.field(
                    title: "Plan model",
                    error: nil
                ) {
                    TextField("same as Model", text: $settings.planModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                }

                SettingsFormChrome.divider

                SettingsFormChrome.field(
                    title: "Execute model",
                    error: nil
                ) {
                    TextField("same as Model", text: $settings.executeModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                }

                SettingsFormChrome.divider

                SettingsFormChrome.field(
                    title: "Review model",
                    error: nil
                ) {
                    TextField("same as Model", text: $settings.reviewModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                }

                SettingsFormChrome.divider

                SettingsFormChrome.field(
                    title: "API Key",
                    error: apiKeyValidationError,
                    isLast: true
                ) {
                    SecureField("sk-…", text: $settings.apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: SageDesign.Typography.bodySize))
                        .foregroundStyle(.primary)
                        .onChange(of: settings.apiKey) { _, _ in onFieldChange() }
                }
            }
            .sagePanelBackground(cornerRadius: 10)

            statusRow
        }
    }

    static func canTest(_ settings: ModelSettings) -> Bool {
        baseURLError(in: settings) == nil
            && modelError(in: settings) == nil
            && apiKeyError(in: settings) == nil
    }

    private var statusRow: some View {
        Group {
            if let persistenceError = settings.apiKeyPersistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                switch testState {
                case .idle:
                    Text("Stored in Keychain · saves automatically")
                        .foregroundStyle(.secondary)
                case .testing:
                    Label("Testing connection…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                case .success:
                    Label("Connection succeeded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
            }
        }
        .font(.system(size: SageDesign.Typography.microSize))
        .padding(.leading, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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
