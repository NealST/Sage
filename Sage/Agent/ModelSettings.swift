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
        /// Legacy plaintext storage — migrated out on launch.
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
                apiKeyPersistenceError = "Could not move API key into Keychain."
            }
        } else {
            apiKey = ""
        }
        isHydrating = false
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
            apiKeyPersistenceError = "Could not save API key to Keychain. Kept a local fallback."
        }
    }
}
