//
//  ModelSettings.swift
//  Sage
//

import Foundation

/// Which sub-agent a completion is for. Empty role-specific fields fall back to `model`.
enum ModelRole: String, Sendable {
    case plan
    case execute
    case review
}

@Observable
@MainActor
final class ModelSettings {
    static let shared = ModelSettings()

    private enum Account {
        static let apiKey = "llm.apiKey"
    }

    private enum DefaultsKey {
        static let baseURL = "llm.baseURL"
        static let model = "llm.model"
        static let planModel = "llm.planModel"
        static let executeModel = "llm.executeModel"
        static let reviewModel = "llm.reviewModel"
        /// Legacy plaintext storage — migrated out on launch.
        static let apiKeyFallback = "llm.apiKey.fallback"
    }

    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: DefaultsKey.baseURL) }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: DefaultsKey.model) }
    }

    /// Empty = use `model`. Thread, skill recall, work plan, and persist judgment.
    var planModel: String {
        didSet { UserDefaults.standard.set(planModel, forKey: DefaultsKey.planModel) }
    }

    /// Empty = use `model`. ReAct / tool loop.
    var executeModel: String {
        didSet { UserDefaults.standard.set(executeModel, forKey: DefaultsKey.executeModel) }
    }

    /// Empty = use `model`. Invisible accept / revise pass.
    var reviewModel: String {
        didSet { UserDefaults.standard.set(reviewModel, forKey: DefaultsKey.reviewModel) }
    }

    var apiKey: String = "" {
        didSet {
            guard !isHydrating else { return }
            persistAPIKey(apiKey)
        }
    }

    /// Surfaced when Keychain persistence fails after an edit.
    private(set) var apiKeyPersistenceError: String?

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isHydrating = true

    private init() {
        baseURL = UserDefaults.standard.string(forKey: DefaultsKey.baseURL)
            ?? "https://api.openai.com/v1"
        model = UserDefaults.standard.string(forKey: DefaultsKey.model)
            ?? "gpt-4.1-mini"
        planModel = UserDefaults.standard.string(forKey: DefaultsKey.planModel) ?? ""
        executeModel = UserDefaults.standard.string(forKey: DefaultsKey.executeModel) ?? ""
        reviewModel = UserDefaults.standard.string(forKey: DefaultsKey.reviewModel) ?? ""

        if let key = KeychainStore.get(account: Account.apiKey), !key.isEmpty {
            apiKey = key
            UserDefaults.standard.removeObject(forKey: DefaultsKey.apiKeyFallback)
        } else if let legacy = UserDefaults.standard.string(forKey: DefaultsKey.apiKeyFallback),
                  !legacy.isEmpty {
            apiKey = legacy
            do {
                try KeychainStore.set(legacy, account: Account.apiKey)
                UserDefaults.standard.removeObject(forKey: DefaultsKey.apiKeyFallback)
            } catch {
                // Keep plaintext until Keychain accepts the key.
                let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                apiKeyPersistenceError = "Could not move API key into Keychain. \(detail)"
            }
        } else {
            apiKey = ""
        }
        isHydrating = false
    }

    func resolvedModel(for role: ModelRole) -> String {
        let override: String
        switch role {
        case .plan: override = planModel
        case .execute: override = executeModel
        case .review: override = reviewModel
        }
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? model : trimmed
    }

    func snapshot(for role: ModelRole) -> ModelSettingsSnapshot {
        ModelSettingsSnapshot(
            baseURL: baseURL,
            model: resolvedModel(for: role),
            apiKey: apiKey
        )
    }

    private func persistAPIKey(_ key: String) {
        apiKeyPersistenceError = nil
        if key.isEmpty {
            KeychainStore.delete(account: Account.apiKey)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.apiKeyFallback)
            return
        }
        do {
            try KeychainStore.set(key, account: Account.apiKey)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.apiKeyFallback)
        } catch {
            // Keep a plaintext fallback so a failed Keychain write doesn't lose the key on quit.
            UserDefaults.standard.set(key, forKey: DefaultsKey.apiKeyFallback)
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            apiKeyPersistenceError = "Could not save API key to Keychain. Kept a local fallback. \(detail)"
        }
    }
}
