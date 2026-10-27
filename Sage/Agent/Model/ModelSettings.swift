//
//  ModelSettings.swift
//  Sage
//

import Foundation

/// Which sub-agent a completion is for. Role-specific selections fall back
/// to `defaultSelection`.
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
        /// JSON-encoded `ModelSelection` values.
        static let defaultSelection = "llm.defaultModelSelection"
        static let planSelection = "llm.planSelection"
        static let executeSelection = "llm.executeSelection"
        static let reviewSelection = "llm.reviewSelection"
        /// Legacy pre-selection string keys — read once for migration, kept
        /// on disk so a rollback build still sees the old values.
        static let legacyModel = "llm.model"
        static let legacyPlanModel = "llm.planModel"
        static let legacyExecuteModel = "llm.executeModel"
        static let legacyReviewModel = "llm.reviewModel"
        static let temperature = "llm.temperature"
        static let requestTimeout = "llm.requestTimeout"
        /// Legacy plaintext storage — migrated out on launch.
        static let apiKeyFallback = "llm.apiKey.fallback"
    }

    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: DefaultsKey.baseURL) }
    }

    /// The model every role uses unless a role-specific selection overrides it.
    var defaultSelection: ModelSelection {
        didSet { defaultSelection.store(forKey: DefaultsKey.defaultSelection) }
    }

    /// `nil` = follow `defaultSelection`. Thread, skill recall, work plan, and persist judgment.
    var planSelection: ModelSelection? {
        didSet { persistSelection(planSelection, forKey: DefaultsKey.planSelection) }
    }

    /// `nil` = follow `defaultSelection`. ReAct / tool loop.
    var executeSelection: ModelSelection? {
        didSet { persistSelection(executeSelection, forKey: DefaultsKey.executeSelection) }
    }

    /// `nil` = follow `defaultSelection`. Invisible accept / revise pass.
    var reviewSelection: ModelSelection? {
        didSet { persistSelection(reviewSelection, forKey: DefaultsKey.reviewSelection) }
    }

    /// Sampling temperature for agent turns. `nil` = provider default.
    var temperature: Double? {
        didSet {
            if let temperature {
                UserDefaults.standard.set(temperature, forKey: DefaultsKey.temperature)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.temperature)
            }
        }
    }

    /// Per-request timeout in seconds, clamped to 30…600.
    var requestTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(requestTimeout, forKey: DefaultsKey.requestTimeout) }
    }

    var apiKey: String = "" {
        didSet {
            guard !isHydrating else { return }
            persistAPIKey(apiKey)
        }
    }

    /// Surfaced when Keychain persistence fails after an edit.
    private(set) var apiKeyPersistenceError: String?

    /// True when at least one role deviates from the default selection.
    var hasRoleOverrides: Bool {
        planSelection != nil || executeSelection != nil || reviewSelection != nil
    }

    var isConfigured: Bool {
        switch defaultSelection.origin {
        case .cloud:
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !defaultSelection.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .local:
            !defaultSelection.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var isHydrating = true

    private init() {
        baseURL = UserDefaults.standard.string(forKey: DefaultsKey.baseURL)
            ?? "https://api.openai.com/v1"

        let selections = Self.loadSelections()
        defaultSelection = selections.defaultSelection
        planSelection = selections.planSelection
        executeSelection = selections.executeSelection
        reviewSelection = selections.reviewSelection

        temperature = UserDefaults.standard.object(forKey: DefaultsKey.temperature) as? Double
        if let storedTimeout = UserDefaults.standard.object(forKey: DefaultsKey.requestTimeout) as? Double {
            requestTimeout = min(max(storedTimeout, 30), 600)
        } else {
            requestTimeout = 120
        }

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
                let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                apiKeyPersistenceError = "Could not move API key into Keychain. Re-save in Settings. \(detail)"
            }
        } else {
            apiKey = ""
        }
        isHydrating = false
    }

    /// Reads the JSON-encoded selections, migrating the legacy string keys
    /// on first launch after the selection model shipped.
    private static func loadSelections() -> ModelSelectionMigration.Result {
        if let stored = ModelSelection.decodeStored(forKey: DefaultsKey.defaultSelection) {
            return ModelSelectionMigration.Result(
                defaultSelection: stored,
                planSelection: ModelSelection.decodeStored(forKey: DefaultsKey.planSelection),
                executeSelection: ModelSelection.decodeStored(forKey: DefaultsKey.executeSelection),
                reviewSelection: ModelSelection.decodeStored(forKey: DefaultsKey.reviewSelection)
            )
        }

        let migrated = ModelSelectionMigration.migrate(.init(
            defaultModel: UserDefaults.standard.string(forKey: DefaultsKey.legacyModel) ?? "",
            planModel: UserDefaults.standard.string(forKey: DefaultsKey.legacyPlanModel),
            executeModel: UserDefaults.standard.string(forKey: DefaultsKey.legacyExecuteModel),
            reviewModel: UserDefaults.standard.string(forKey: DefaultsKey.legacyReviewModel)
        ))
        migrated.defaultSelection.store(forKey: DefaultsKey.defaultSelection)
        migrated.planSelection?.store(forKey: DefaultsKey.planSelection)
        migrated.executeSelection?.store(forKey: DefaultsKey.executeSelection)
        migrated.reviewSelection?.store(forKey: DefaultsKey.reviewSelection)
        return migrated
    }

    /// The selection a given sub-agent runs on.
    func resolvedSelection(for role: ModelRole) -> ModelSelection {
        switch role {
        case .plan: return planSelection ?? defaultSelection
        case .execute: return executeSelection ?? defaultSelection
        case .review: return reviewSelection ?? defaultSelection
        }
    }

    /// Model id for a role — convenience for labels and probes.
    func resolvedModel(for role: ModelRole) -> String {
        resolvedSelection(for: role).identifier
    }

    func snapshot(for role: ModelRole) -> ModelSettingsSnapshot {
        let selection = resolvedSelection(for: role)
        switch selection.origin {
        case .cloud:
            return ModelSettingsSnapshot(
                baseURL: baseURL,
                model: selection.identifier,
                apiKey: apiKey,
                temperature: temperature,
                requestTimeout: requestTimeout,
                origin: .cloud
            )
        case .local:
            return ModelSettingsSnapshot(
                baseURL: LocalModelServer.shared.baseURLString,
                model: selection.identifier,
                apiKey: "",
                temperature: temperature,
                requestTimeout: requestTimeout,
                origin: .local
            )
        }
    }

    private func persistSelection(_ selection: ModelSelection?, forKey key: String) {
        if let selection {
            selection.store(forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
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
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            apiKeyPersistenceError = "Could not save API key to Keychain. It was not stored. \(detail)"
        }
    }
}
