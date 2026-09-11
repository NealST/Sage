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
    @Environment(\.sageTypography) private var type
    var onFieldChange: () -> Void
    /// First-run courtesy: "required" errors appear only after a field was
    /// touched, so a pristine form doesn't greet a new user with red marks.
    /// System errors (Keychain failures) always show.
    @State private var touchedFields: Set<String> = []

    var body: some View {
        Section {
            connectionField(
                "Base URL",
                text: $settings.baseURL,
                prompt: "https://api.openai.com/v1",
                validation: Self.baseURLError
            )

            connectionField(
                "Model",
                text: $settings.model,
                prompt: "gpt-4.1-mini",
                validation: Self.modelError
            )

            connectionField("Plan model", text: $settings.planModel, prompt: "same as Model")
            connectionField("Execute model", text: $settings.executeModel, prompt: "same as Model")
            connectionField("Review model", text: $settings.reviewModel, prompt: "same as Model")

            LabeledContent("API Key") {
                VStack(alignment: .trailing, spacing: 4) {
                    SecureField("sk-…", text: $settings.apiKey)
                        .onChange(of: settings.apiKey) { _, _ in
                            touchedFields.insert("API Key")
                            onFieldChange()
                        }
                    if let apiKeyValidationError {
                        Text(apiKeyValidationError)
                            .sageFont(type.caption)
                            .foregroundStyle(SageDesign.Palette.danger)
                    }
                }
            }

            LabeledContent("Temperature") {
                HStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { settings.temperature ?? Self.defaultTemperature },
                            set: { settings.temperature = $0 }
                        ),
                        in: 0...2,
                        step: 0.1
                    )
                    .frame(width: 180)
                    Text(temperatureLabel)
                        .sageFont(type.caption)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(settings.temperature == nil ? .secondary : .primary)
                    if settings.temperature != nil {
                        Button("Reset") { settings.temperature = nil }
                            .buttonStyle(.link)
                            .controlSize(.small)
                            .help("Send requests without a temperature and use the provider default")
                    }
                }
            }
            .help("Sampling randomness for agent replies. Drag to override the provider default.")

            LabeledContent("Request timeout") {
                Stepper(
                    value: Binding(
                        get: { settings.requestTimeout },
                        set: { settings.requestTimeout = min(max($0, 30), 600) }
                    ),
                    in: 30...600,
                    step: 30
                ) {
                    Text("\(Int(settings.requestTimeout)) s")
                        .sageFont(type.caption)
                        .monospacedDigit()
                }
            }
            .help("How long Sage waits for a model response before retrying.")
        }
    }

    private var temperatureLabel: String {
        settings.temperature.map { value in
            value.formatted(.number.precision(.fractionLength(1)))
        } ?? "Default"
    }

    private static let defaultTemperature = 0.7

    static func canTest(_ settings: ModelSettings) -> Bool {
        baseURLError(in: settings) == nil
            && modelError(in: settings) == nil
            && apiKeyError(in: settings) == nil
    }

    private func connectionField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        validation: ((ModelSettings) -> String?)? = nil
    ) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(prompt, text: text)
                    .onChange(of: text.wrappedValue) { _, _ in
                        touchedFields.insert(title)
                        onFieldChange()
                    }
                if touchedFields.contains(title), let error = validation?(settings) {
                    Text(error)
                        .sageFont(type.caption)
                        .foregroundStyle(SageDesign.Palette.danger)
                }
            }
        }
    }

    private var apiKeyValidationError: String? {
        if settings.apiKeyPersistenceError != nil { return settings.apiKeyPersistenceError }
        guard touchedFields.contains("API Key") else { return nil }
        return Self.apiKeyError(in: settings)
    }

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

/// Connection status — rendered in the footer of the Test Connection section
/// so the outcome sits next to the button that caused it.
struct ConnectionStatusRow: View {
    let settings: ModelSettings
    var testState: SettingsConnectionTestState

    var body: some View {
        Group {
            if let persistenceError = settings.apiKeyPersistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(SageDesign.Palette.danger)
            } else {
                switch testState {
                case .idle:
                    Text(idleText)

                case .testing:
                    Label("Testing connection…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)

                case .success:
                    Label("Connection succeeded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(SageDesign.Palette.success)

                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(SageDesign.Palette.danger)
                }
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var idleText: String {
        if settings.isConfigured {
            return "Stored in Keychain · saves automatically"
        }
        return "Not connected yet — paste your provider’s API key and model, then test the connection."
    }

    private var accessibilityText: String {
        if let persistenceError = settings.apiKeyPersistenceError {
            return persistenceError
        }
        switch testState {
        case .idle: return idleText
        case .testing: return "Testing connection"
        case .success: return "Connection succeeded"
        case .failure(let message): return message
        }
    }
}
