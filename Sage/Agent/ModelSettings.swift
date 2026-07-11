//
//  ModelSettings.swift
//  Sage
//

import Foundation

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
        /// Debug-friendly fallback so Xcode re-runs don't depend on Keychain ACL.
        static let apiKeyFallback = "llm.apiKey.fallback"
    }

    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: DefaultsKey.baseURL) }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: DefaultsKey.model) }
    }

    var apiKey: String = "" {
        didSet {
            guard !isHydrating else { return }
            persistAPIKey(apiKey)
        }
    }

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

        // UserDefaults first — never blocks launch with a Keychain password dialog.
        // Keychain is best-effort for slightly better persistence.
        if let fallback = UserDefaults.standard.string(forKey: DefaultsKey.apiKeyFallback), !fallback.isEmpty {
            apiKey = fallback
        } else if let key = KeychainStore.get(account: Account.apiKey), !key.isEmpty {
            apiKey = key
            UserDefaults.standard.set(key, forKey: DefaultsKey.apiKeyFallback)
        } else {
            apiKey = ""
        }
        isHydrating = false
    }

    private func persistAPIKey(_ key: String) {
        if key.isEmpty {
            KeychainStore.delete(account: Account.apiKey)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.apiKeyFallback)
            return
        }
        UserDefaults.standard.set(key, forKey: DefaultsKey.apiKeyFallback)
        try? KeychainStore.set(key, account: Account.apiKey)
    }
}
