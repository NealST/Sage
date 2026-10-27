//
//  ModelSelection.swift
//  Sage
//
//  Identifies one model offered by a supply source. Cloud selections are
//  provider model ids; local selections are Hugging Face repo ids whose
//  weights MLX serves through the in-process OpenAI-compatible server.
//

import Foundation

enum ModelOrigin: String, Codable, Sendable, CaseIterable {
    case cloud
    case local
}

struct ModelSelection: Codable, Equatable, Hashable, Sendable {
    var origin: ModelOrigin
    /// Cloud: model id sent to the provider. Local: Hugging Face repo id,
    /// e.g. "mlx-community/Qwen3-4B-4bit".
    var identifier: String

    init(origin: ModelOrigin, identifier: String) {
        self.origin = origin
        self.identifier = identifier
    }

    static func cloud(_ identifier: String) -> ModelSelection {
        ModelSelection(origin: .cloud, identifier: identifier)
    }

    static func local(_ identifier: String) -> ModelSelection {
        ModelSelection(origin: .local, identifier: identifier)
    }

    /// Short label for chips and menus: repo id drops the org segment.
    var displayName: String {
        guard origin == .local, identifier.contains("/") else { return identifier }
        return String(identifier.split(separator: "/").last ?? Substring(identifier))
    }

    // MARK: - Persistence

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Warms the on-device engine when this selection points at a local
    /// model, so the first turn doesn't wait on a multi-GB load.
    func warmUpLocalEngineIfApplicable() {
        guard origin == .local, LocalModelEngine.isAvailable else { return }
        let identifier = self.identifier
        Task {
            await LocalModelEngine.shared.warmUp(modelID: identifier)
        }
    }

    static func decode(from data: Data) -> ModelSelection? {
        try? JSONDecoder().decode(ModelSelection.self, from: data)
    }

    static func decodeStored(forKey key: String) -> ModelSelection? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return decode(from: data)
    }

    func store(forKey key: String) {
        if let data = encoded() {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Pure migration from the pre-selection string settings. Kept free of
/// UserDefaults access so it stays unit-testable.
enum ModelSelectionMigration {
    struct LegacyStrings: Sendable {
        var defaultModel: String
        var planModel: String?
        var executeModel: String?
        var reviewModel: String?
    }

    struct Result: Sendable {
        var defaultSelection: ModelSelection
        var planSelection: ModelSelection?
        var executeSelection: ModelSelection?
        var reviewSelection: ModelSelection?
    }

    static func migrate(_ legacy: LegacyStrings) -> Result {
        func cloudOrNil(_ raw: String?) -> ModelSelection? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .cloud(trimmed)
        }

        let fallback = legacy.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            defaultSelection: cloudOrNil(legacy.defaultModel)
                ?? .cloud(fallback.isEmpty ? "gpt-4.1-mini" : fallback),
            planSelection: cloudOrNil(legacy.planModel),
            executeSelection: cloudOrNil(legacy.executeModel),
            reviewSelection: cloudOrNil(legacy.reviewModel)
        )
    }
}
