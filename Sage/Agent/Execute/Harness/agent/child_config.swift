//
//  child_config.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/child_config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Pure helpers (`model_supports_multi_agent_backend`, fork rejection,
//  model-name lookup, reasoning-effort validation, override resolution)
//  are faithful. `prepare_agent_spawn_config` and shared-config builders
//  wait on Session / TurnContext / Config.
//

import CodexProtocol
import Foundation

public let MAX_SPAWN_AGENT_MODEL_OVERRIDES = 5

public func modelSupportsMultiAgentBackend(
    _ model: ModelPreset,
    multiAgentVersion: MultiAgentVersion
) -> Bool {
    multiAgentVersion != .v2 || model.multiAgentVersion != .disabled
}

public enum SpawnConfigVersion: Equatable, Sendable {
    case v1
    case v2
}

public struct SpawnConfigOptions: Equatable, Sendable {
    public var version: SpawnConfigVersion
    public var fullHistoryFork: Bool
    public var roleName: String?
    public var model: String?
    public var reasoningEffort: ReasoningEffort?

    public init(
        version: SpawnConfigVersion,
        fullHistoryFork: Bool,
        roleName: String? = nil,
        model: String? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) {
        self.version = version
        self.fullHistoryFork = fullHistoryFork
        self.roleName = roleName
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public func prepareAgentSpawnConfig(_ options: SpawnConfigOptions) async throws -> Never {
    throw CodexErr.unsupportedOperation(
        "prepare_agent_spawn_config waits on Session / StepContext / Config"
    )
}

public func buildAgentSpawnConfig() throws -> Never {
    throw CodexErr.unsupportedOperation(
        "build_agent_spawn_config waits on BaseInstructions / StepContext / Config"
    )
}

public func buildAgentResumeConfig() throws -> Never {
    throw CodexErr.unsupportedOperation("build_agent_resume_config waits on TurnContext / Config")
}

public func rejectFullForkAgentTypeOverride(_ agentType: String?) throws {
    if agentType != nil {
        throw CodexErr.invalidRequest(
            "Full-history forked agents inherit the parent agent type; omit agent_type, or spawn without a full-history fork."
        )
    }
}

public func findSpawnAgentModelName(
    availableModels: [ModelPreset],
    requestedModel: String,
    multiAgentVersion: MultiAgentVersion
) throws -> String {
    if let model = availableModels.first(where: { candidate in
        candidate.model == requestedModel
            && modelSupportsMultiAgentBackend(candidate, multiAgentVersion: multiAgentVersion)
    }) {
        return model.model
    }
    let available = availableModels
        .filter(\.showInPicker)
        .filter { modelSupportsMultiAgentBackend($0, multiAgentVersion: multiAgentVersion) }
        .prefix(MAX_SPAWN_AGENT_MODEL_OVERRIDES)
        .map(\.model)
        .joined(separator: ", ")
    throw CodexErr.invalidRequest(
        "Unknown model `\(requestedModel)` for spawn_agent. Available models: \(available)"
    )
}

public func validateSpawnAgentReasoningEffort(
    model: String,
    supportedReasoningLevels: [ReasoningEffortPreset],
    requestedReasoningEffort: ReasoningEffort
) throws {
    if supportedReasoningLevels.contains(where: { $0.effort == requestedReasoningEffort }) {
        return
    }
    let supported = supportedReasoningLevels
        .map { $0.effort.asStr }
        .joined(separator: ", ")
    throw CodexErr.invalidRequest(
        "Reasoning effort `\(requestedReasoningEffort.asStr)` is not supported for model `\(model)`. Supported reasoning efforts: \(supported)"
    )
}

public struct SpawnModelOverrideResolution: Equatable, Sendable {
    public var model: String?
    public var reasoningEffort: ReasoningEffort?

    public init(model: String? = nil, reasoningEffort: ReasoningEffort? = nil) {
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public let SERVICE_TIER_DEFAULT_REQUEST_VALUE = "default"

public func resolveRequestedSpawnAgentModelOverrides(
    availableModels: [ModelPreset],
    multiAgentVersion: MultiAgentVersion,
    requestedModel: String?,
    requestedReasoningEffort: ReasoningEffort?,
    fallbackModel: String,
    fallbackSupportedReasoningLevels: [ReasoningEffortPreset]
) throws -> SpawnModelOverrideResolution {
    if requestedModel == nil && requestedReasoningEffort == nil {
        return SpawnModelOverrideResolution()
    }
    if let requestedModel {
        let selectedModelName = try findSpawnAgentModelName(
            availableModels: availableModels,
            requestedModel: requestedModel,
            multiAgentVersion: multiAgentVersion
        )
        let selected = availableModels.first { $0.model == selectedModelName }
        if let requestedReasoningEffort {
            try validateSpawnAgentReasoningEffort(
                model: selectedModelName,
                supportedReasoningLevels: selected?.supportedReasoningEfforts
                    ?? fallbackSupportedReasoningLevels,
                requestedReasoningEffort: requestedReasoningEffort
            )
            return SpawnModelOverrideResolution(
                model: selectedModelName,
                reasoningEffort: requestedReasoningEffort
            )
        }
        return SpawnModelOverrideResolution(
            model: selectedModelName,
            reasoningEffort: selected?.defaultReasoningEffort
        )
    }
    if let requestedReasoningEffort {
        try validateSpawnAgentReasoningEffort(
            model: fallbackModel,
            supportedReasoningLevels: fallbackSupportedReasoningLevels,
            requestedReasoningEffort: requestedReasoningEffort
        )
        return SpawnModelOverrideResolution(reasoningEffort: requestedReasoningEffort)
    }
    return SpawnModelOverrideResolution()
}

public func resolveSpawnAgentServiceTier(
    requestedTier: String?,
    modelSupportsServiceTier: (String) -> Bool
) -> String? {
    guard let requestedTier else { return nil }
    if requestedTier == SERVICE_TIER_DEFAULT_REQUEST_VALUE {
        return requestedTier
    }
    return modelSupportsServiceTier(requestedTier) ? requestedTier : nil
}

public func applySpawnAgentServiceTier() async throws {
    throw CodexErr.unsupportedOperation(
        "apply_spawn_agent_service_tier waits on Session / ModelsManager / Config"
    )
}
