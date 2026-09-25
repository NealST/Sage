//
//  openai_models.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/openai_models.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Shared model metadata types exchanged between Codex services and clients.
//  `strum::Display`, `strum::EnumIter`, `schemars::JsonSchema`, and `ts_rs::TS`
//  are omitted (no runtime JSON-schema or TypeScript binding generation needed).
//
//  `ReasoningEffort` is defined in config_types.swift; all files are in the same
//  CodexProtocol module so no import is needed.
//
//  `chrono::DateTime<Utc>` is mapped to Foundation `Date` with custom RFC-3339
//  Codable helpers.
//

import Foundation

// MARK: - Forward declarations for types in files not yet fully ported

/// Multi-agent protocol version. Will live in protocol.swift eventually.
public enum MultiAgentVersion: String, Codable, Equatable, Sendable {
    case disabled = "disabled"
    case v1 = "v1"
    case v2 = "v2"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let known = MultiAgentVersion(rawValue: raw) {
            self = known
        } else {
            // Unknown versions treated as nil at call site via optional decoding.
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown MultiAgentVersion: \(raw)")
        }
    }
}

/// Access program for cyber-specialty models (from turn_input.rs).
public enum CyberAccessProgram: String, Codable, Equatable, Sendable {
    case standard
    case daybreakBlue = "daybreak_blue"
    case daybreakRed = "daybreak_red"
}

// MARK: - Constants

public let modelSpecialtyCyber = "cyber"
public let speedTierFast = "fast"

// MARK: - InputModality

public enum InputModality: String, Codable, Equatable, Hashable, Sendable {
    case text
    case image
    case audio
}

public func defaultInputModalities() -> [InputModality] {
    [.text, .image]
}

// MARK: - ReasoningEffortPreset

public struct ReasoningEffortPreset: Codable, Equatable, Sendable {
    public var effort: ReasoningEffort
    public var description: String
}

// MARK: - ModelUpgrade

public struct ModelUpgrade: Codable, Equatable, Sendable {
    public var id: String
    public var migrationConfigKey: String
    public var modelLink: String?
    public var upgradeCopy: String?
    public var migrationMarkdown: String?
    public var retirementAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case migrationConfigKey = "migration_config_key"
        case modelLink = "model_link"
        case upgradeCopy = "upgrade_copy"
        case migrationMarkdown = "migration_markdown"
        case retirementAt = "retirement_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        migrationConfigKey = try container.decode(String.self, forKey: .migrationConfigKey)
        modelLink = try container.decodeIfPresent(String.self, forKey: .modelLink)
        upgradeCopy = try container.decodeIfPresent(String.self, forKey: .upgradeCopy)
        migrationMarkdown = try container.decodeIfPresent(String.self, forKey: .migrationMarkdown)
        retirementAt = try decodeOptionalRFC3339(container: container, forKey: .retirementAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(migrationConfigKey, forKey: .migrationConfigKey)
        try container.encodeIfPresent(modelLink, forKey: .modelLink)
        try container.encodeIfPresent(upgradeCopy, forKey: .upgradeCopy)
        try container.encodeIfPresent(migrationMarkdown, forKey: .migrationMarkdown)
        try encodeOptionalRFC3339(retirementAt, container: &container, forKey: .retirementAt)
    }

    public init(
        id: String, migrationConfigKey: String, modelLink: String? = nil,
        upgradeCopy: String? = nil, migrationMarkdown: String? = nil, retirementAt: Date? = nil
    ) {
        self.id = id; self.migrationConfigKey = migrationConfigKey
        self.modelLink = modelLink; self.upgradeCopy = upgradeCopy
        self.migrationMarkdown = migrationMarkdown; self.retirementAt = retirementAt
    }
}

// MARK: - ModelAvailabilityNux

public struct ModelAvailabilityNux: Codable, Equatable, Sendable {
    public var message: String
}

// MARK: - ModelServiceTier

public struct ModelServiceTier: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
}

// MARK: - ModelPreset

public struct ModelPreset: Codable, Equatable, Sendable {
    public var id: String
    public var model: String
    public var displayName: String
    public var description: String
    public var modelSpecialty: String?
    public var defaultReasoningEffort: ReasoningEffort
    public var supportedReasoningEfforts: [ReasoningEffortPreset]
    public var supportsPersonality: Bool
    public var additionalSpeedTiers: [String]
    public var serviceTiers: [ModelServiceTier]
    public var defaultServiceTier: String?
    public var availableAccessPrograms: ModelAccessPrograms?
    public var isDefault: Bool
    public var upgrade: ModelUpgrade?
    public var showInPicker: Bool
    public var multiAgentVersion: MultiAgentVersion?
    public var availabilityNux: ModelAvailabilityNux?
    public var supportedInApi: Bool
    public var inputModalities: [InputModality]

    enum CodingKeys: String, CodingKey {
        case id, model
        case displayName = "display_name"
        case description
        case modelSpecialty = "model_specialty"
        case defaultReasoningEffort = "default_reasoning_effort"
        case supportedReasoningEfforts = "supported_reasoning_efforts"
        case supportsPersonality = "supports_personality"
        case additionalSpeedTiers = "additional_speed_tiers"
        case serviceTiers = "service_tiers"
        case defaultServiceTier = "default_service_tier"
        case availableAccessPrograms = "available_access_programs"
        case isDefault = "is_default"
        case upgrade
        case showInPicker = "show_in_picker"
        case availabilityNux = "availability_nux"
        case supportedInApi = "supported_in_api"
        case inputModalities = "input_modalities"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        model = try container.decode(String.self, forKey: .model)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        modelSpecialty = try container.decodeIfPresent(String.self, forKey: .modelSpecialty)
        defaultReasoningEffort = try container.decode(ReasoningEffort.self, forKey: .defaultReasoningEffort)
        supportedReasoningEfforts = try container.decode([ReasoningEffortPreset].self, forKey: .supportedReasoningEfforts)
        supportsPersonality = try container.decodeIfPresent(Bool.self, forKey: .supportsPersonality) ?? false
        additionalSpeedTiers = try container.decodeIfPresent([String].self, forKey: .additionalSpeedTiers) ?? []
        serviceTiers = try container.decodeIfPresent([ModelServiceTier].self, forKey: .serviceTiers) ?? []
        defaultServiceTier = try container.decodeIfPresent(String.self, forKey: .defaultServiceTier)
        availableAccessPrograms = try container.decodeIfPresent(ModelAccessPrograms.self, forKey: .availableAccessPrograms)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        upgrade = try container.decodeIfPresent(ModelUpgrade.self, forKey: .upgrade)
        showInPicker = try container.decode(Bool.self, forKey: .showInPicker)
        // multi_agent_version is skip_serializing/skip_deserializing in upstream
        multiAgentVersion = nil
        availabilityNux = try container.decodeIfPresent(ModelAvailabilityNux.self, forKey: .availabilityNux)
        supportedInApi = try container.decode(Bool.self, forKey: .supportedInApi)
        inputModalities = try container.decodeIfPresent([InputModality].self, forKey: .inputModalities) ?? defaultInputModalities()
    }
}

extension ModelPreset {
    public func supportsFastMode() -> Bool {
        serviceTiers.contains(where: { $0.id == ServiceTier.fast.requestValue })
            || additionalSpeedTiers.contains(speedTierFast)
    }

    public static func filterByAuth(_ models: [ModelPreset], chatgptMode: Bool) -> [ModelPreset] {
        models.filter { chatgptMode || $0.supportedInApi }
    }

    public static func markDefaultByPickerVisibility(_ models: inout [ModelPreset]) {
        for i in models.indices { models[i].isDefault = false }
        if let idx = models.firstIndex(where: { $0.showInPicker }) {
            models[idx].isDefault = true
        } else if !models.isEmpty {
            models[0].isDefault = true
        }
    }
}

// MARK: - ModelVisibility

public enum ModelVisibility: String, Codable, Equatable, Sendable {
    case list
    case hide
    case none
}

// MARK: - ConfigShellToolType

public enum ConfigShellToolType: Equatable, Sendable {
    case unifiedExec
    case disabled
}

extension ConfigShellToolType: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "unified_exec", "default", "local", "shell_command":
            self = .unifiedExec
        case "disabled":
            self = .disabled
        default:
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown ConfigShellToolType: \(raw)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unifiedExec: try container.encode("unified_exec")
        case .disabled: try container.encode("disabled")
        }
    }
}

// MARK: - ApplyPatchToolType

public enum ApplyPatchToolType: String, Codable, Equatable, Hashable, Sendable {
    case freeform
}

// MARK: - WebSearchToolType

public enum WebSearchToolType: String, Codable, Equatable, Hashable, Sendable {
    case text
    case textAndImage = "text_and_image"
}

// MARK: - TruncationMode

public enum TruncationMode: String, Codable, Equatable, Sendable {
    case bytes
    case tokens
}

// MARK: - ToolMode

public enum ToolMode: String, Codable, Equatable, Sendable {
    case direct
    case codeMode = "code_mode"
    case codeModeOnly = "code_mode_only"
}

// MARK: - TruncationPolicyConfig

public struct TruncationPolicyConfig: Codable, Equatable, Sendable {
    public var mode: TruncationMode
    public var limit: Int64

    public static func bytes(_ limit: Int64) -> TruncationPolicyConfig {
        TruncationPolicyConfig(mode: .bytes, limit: limit)
    }

    public static func tokens(_ limit: Int64) -> TruncationPolicyConfig {
        TruncationPolicyConfig(mode: .tokens, limit: limit)
    }
}

// MARK: - ClientVersion

public struct ClientVersion: Codable, Equatable, Sendable {
    public var major: Int32
    public var minor: Int32
    public var patch: Int32

    public init(_ major: Int32, _ minor: Int32, _ patch: Int32) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        major = try container.decode(Int32.self)
        minor = try container.decode(Int32.self)
        patch = try container.decode(Int32.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(major)
        try container.encode(minor)
        try container.encode(patch)
    }
}

// MARK: - GuardianReviewMode

public enum GuardianReviewMode: String, Codable, Equatable, Sendable {
    case disabled
    case synchronous
    case adaptive
    case unknown

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = GuardianReviewMode(rawValue: raw) ?? .unknown
    }
}

// MARK: - GuardianUnscoredAction

public enum GuardianUnscoredAction: String, Codable, Equatable, Sendable {
    case ignore
    case ageScore = "age_score"
    case invalidateScore = "invalidate_score"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = GuardianUnscoredAction(rawValue: raw) ?? .invalidateScore
    }
}

// MARK: - GuardianModelPolicy

public struct GuardianModelPolicy: Codable, Equatable, Sendable {
    public var computerUse: GuardianReviewMode?
    public var shell: GuardianReviewMode?
    public var fileChanges: GuardianReviewMode?
    public var mcp: GuardianReviewMode?
    public var network: GuardianReviewMode?
    public var permissions: GuardianReviewMode?
    public var otherTools: GuardianReviewMode
    public var unscoredAction: GuardianUnscoredAction
    public var initialCuaCall: Bool?
    public var sandboxedExecCommands: Bool?

    enum CodingKeys: String, CodingKey {
        case computerUse = "computer_use"
        case shell
        case fileChanges = "file_changes"
        case mcp, network, permissions
        case otherTools = "other_tools"
        case unscoredAction = "unscored_action"
        case initialCuaCall = "initial_cua_call"
        case sandboxedExecCommands = "sandboxed_exec_commands"
    }

    public init(
        computerUse: GuardianReviewMode? = nil,
        shell: GuardianReviewMode? = nil,
        fileChanges: GuardianReviewMode? = nil,
        mcp: GuardianReviewMode? = nil,
        network: GuardianReviewMode? = nil,
        permissions: GuardianReviewMode? = nil,
        otherTools: GuardianReviewMode = .disabled,
        unscoredAction: GuardianUnscoredAction = .invalidateScore,
        initialCuaCall: Bool? = nil,
        sandboxedExecCommands: Bool? = nil
    ) {
        self.computerUse = computerUse; self.shell = shell
        self.fileChanges = fileChanges; self.mcp = mcp
        self.network = network; self.permissions = permissions
        self.otherTools = otherTools; self.unscoredAction = unscoredAction
        self.initialCuaCall = initialCuaCall
        self.sandboxedExecCommands = sandboxedExecCommands
    }

    public func reviewMode(_ scope: GuardianScope) -> GuardianReviewMode {
        let mode: GuardianReviewMode?
        switch scope {
        case .computerUse: mode = computerUse
        case .shell: mode = shell
        case .fileChanges: mode = fileChanges
        case .mcp: mode = mcp
        case .network: mode = network
        case .permissions: mode = permissions
        }
        return mode ?? .disabled
    }

    public func scoringEnabled() -> Bool {
        [computerUse, shell, fileChanges, mcp, network, permissions]
            .contains(.some(.adaptive))
    }

    public mutating func disableScoring() {
        func replaceAdaptive(_ mode: inout GuardianReviewMode?) {
            if mode == .adaptive { mode = .synchronous }
        }
        replaceAdaptive(&computerUse)
        replaceAdaptive(&shell)
        replaceAdaptive(&fileChanges)
        replaceAdaptive(&mcp)
        replaceAdaptive(&network)
        replaceAdaptive(&permissions)
        otherTools = .synchronous
    }

    public func allowsInitialCuaCall() -> Bool {
        initialCuaCall ?? (computerUse == .adaptive)
    }
}

// MARK: - GuardianScope

public enum GuardianScope: Equatable, Sendable {
    case computerUse
    case shell
    case fileChanges
    case mcp
    case network
    case permissions

    public static func forMcpServer(_ server: String) -> GuardianScope {
        forMcpConnector(server, connectorId: nil)
    }

    public static func forMcpConnector(_ server: String, connectorId: String?) -> GuardianScope {
        if isNodeReplBackedConnector(server, connectorId: connectorId) {
            return .computerUse
        }
        return .mcp
    }

    public static func forTool(_ tool: ToolName) -> GuardianScope? {
        if isNodeReplBackedTool(name: tool.name, namespace: tool.namespace) {
            return .computerUse
        }
        if tool.namespace.map({ $0.hasPrefix("mcp__") }) == true
            || tool.name.hasPrefix("mcp__") {
            return .mcp
        }
        guard tool.isDefaultNamespace() else { return nil }
        switch tool.name {
        case "shell", "shell_command", "exec_command", "write_stdin", "execve":
            return .shell
        case "apply_patch":
            return .fileChanges
        case "request_permissions":
            return .permissions
        default:
            return nil
        }
    }
}

// MARK: - GuardianV2ModelConfig

public struct GuardianV2ModelConfig: Codable, Equatable, Sendable {
    public var classifierInstructions: String?
    public var reviewThresholdBasisPoints: UInt16?
    public var maxToolCallLag: Int?
    public var reasoningEffort: ReasoningEffort?
    public var transcript: GuardianV2TranscriptModelConfig?
    public var maxActionTokens: Int?
    public var maxClassifierInstructionTokens: Int?
    public var reuseParentCompaction: Bool?
    public var maxParentCompactionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case classifierInstructions = "classifier_instructions"
        case reviewThresholdBasisPoints = "review_threshold_basis_points"
        case maxToolCallLag = "max_tool_call_lag"
        case reasoningEffort = "reasoning_effort"
        case transcript
        case maxActionTokens = "max_action_tokens"
        case maxClassifierInstructionTokens = "max_classifier_instruction_tokens"
        case reuseParentCompaction = "reuse_parent_compaction"
        case maxParentCompactionTokens = "max_parent_compaction_tokens"
    }

    public init(
        classifierInstructions: String? = nil,
        reviewThresholdBasisPoints: UInt16? = nil,
        maxToolCallLag: Int? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        transcript: GuardianV2TranscriptModelConfig? = nil,
        maxActionTokens: Int? = nil,
        maxClassifierInstructionTokens: Int? = nil,
        reuseParentCompaction: Bool? = nil,
        maxParentCompactionTokens: Int? = nil
    ) {
        self.classifierInstructions = classifierInstructions
        self.reviewThresholdBasisPoints = reviewThresholdBasisPoints
        self.maxToolCallLag = maxToolCallLag
        self.reasoningEffort = reasoningEffort
        self.transcript = transcript
        self.maxActionTokens = maxActionTokens
        self.maxClassifierInstructionTokens = maxClassifierInstructionTokens
        self.reuseParentCompaction = reuseParentCompaction
        self.maxParentCompactionTokens = maxParentCompactionTokens
    }
}

// MARK: - GuardianV2TranscriptModelConfig

public struct GuardianV2TranscriptModelConfig: Codable, Equatable, Sendable {
    public var sources: [String]?
    public var includeImages: Bool?
    public var maxMessageEntryTokens: Int?
    public var maxToolEntryTokens: Int?
    public var maxMessageTranscriptTokens: Int?
    public var maxToolTranscriptTokens: Int?
    public var maxRecentNonUserEntries: Int?

    enum CodingKeys: String, CodingKey {
        case sources
        case includeImages = "include_images"
        case maxMessageEntryTokens = "max_message_entry_tokens"
        case maxToolEntryTokens = "max_tool_entry_tokens"
        case maxMessageTranscriptTokens = "max_message_transcript_tokens"
        case maxToolTranscriptTokens = "max_tool_transcript_tokens"
        case maxRecentNonUserEntries = "max_recent_non_user_entries"
    }

    public init(
        sources: [String]? = nil,
        includeImages: Bool? = nil,
        maxMessageEntryTokens: Int? = nil,
        maxToolEntryTokens: Int? = nil,
        maxMessageTranscriptTokens: Int? = nil,
        maxToolTranscriptTokens: Int? = nil,
        maxRecentNonUserEntries: Int? = nil
    ) {
        self.sources = sources; self.includeImages = includeImages
        self.maxMessageEntryTokens = maxMessageEntryTokens
        self.maxToolEntryTokens = maxToolEntryTokens
        self.maxMessageTranscriptTokens = maxMessageTranscriptTokens
        self.maxToolTranscriptTokens = maxToolTranscriptTokens
        self.maxRecentNonUserEntries = maxRecentNonUserEntries
    }
}

// MARK: - ModelAccessPrograms

public struct ModelAccessPrograms: Codable, Equatable, Sendable {
    public var cyber: [CyberAccessProgram]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String].self, forKey: .cyber)
        cyber = raw.compactMap { CyberAccessProgram(rawValue: $0) }
    }

    enum CodingKeys: String, CodingKey { case cyber }

    public init(cyber: [CyberAccessProgram]) { self.cyber = cyber }
}

// MARK: - ModelInfo

public struct ModelInfo: Codable, Equatable, Sendable {
    public var guardian: GuardianModelPolicy?
    public var slug: String
    public var displayName: String
    public var description: String?
    public var defaultReasoningLevel: ReasoningEffort?
    public var supportedReasoningLevels: [ReasoningEffortPreset]
    public var shellType: ConfigShellToolType
    public var visibility: ModelVisibility
    public var supportedInApi: Bool
    public var priority: Int32
    public var additionalSpeedTiers: [String]
    public var serviceTiers: [ModelServiceTier]
    public var defaultServiceTier: String?
    public var availableAccessPrograms: ModelAccessPrograms?
    public var availabilityNux: ModelAvailabilityNux?
    public var upgrade: ModelInfoUpgrade?
    public var modelMessages: ModelMessages?
    public var includeSkillsUsageInstructions: Bool
    public var includePluginUsageInstructions: Bool
    public var includeAppsUsageInstructions: Bool
    public var supportsReasoningSummaryParameter: Bool
    public var defaultReasoningSummary: ReasoningSummary
    public var supportVerbosity: Bool
    public var defaultVerbosity: Verbosity?
    public var applyPatchToolType: ApplyPatchToolType?
    public var webSearchToolType: WebSearchToolType
    public var truncationPolicy: TruncationPolicyConfig
    public var supportsImageDetailOriginal: Bool
    public var contextWindow: Int64?
    public var maxContextWindow: Int64?
    public var autoCompactTokenLimitValue: Int64?
    public var compHash: String?
    public var effectiveContextWindowPercent: Int64
    public var experimentalSupportedTools: [String]
    public var inputModalities: [InputModality]
    public var usedFallbackModelMetadata: Bool
    public var supportsSearchTool: Bool
    public var supportsExperimentalContext: Bool
    public var useResponsesLite: Bool
    public var supportsReasoningEffortUpdates: Bool
    public var nodeReplAutoReviewRequired: Bool
    public var nodeReplDisabled: Bool
    public var autoReviewModelOverride: String?
    public var modelSpecialty: String?
    public var toolMode: ToolMode?
    public var multiAgentVersion: MultiAgentVersion?
    public var multiAgentReasoningEffort: ReasoningEffort?

    enum CodingKeys: String, CodingKey {
        case guardian, slug
        case displayName = "display_name"
        case description
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
        case shellType = "shell_type"
        case visibility
        case supportedInApi = "supported_in_api"
        case priority
        case additionalSpeedTiers = "additional_speed_tiers"
        case serviceTiers = "service_tiers"
        case defaultServiceTier = "default_service_tier"
        case availableAccessPrograms = "available_access_programs"
        case availabilityNux = "availability_nux"
        case upgrade
        case modelMessages = "model_messages"
        case includeSkillsUsageInstructions = "include_skills_usage_instructions"
        case includePluginUsageInstructions = "include_plugin_usage_instructions"
        case includeAppsUsageInstructions = "include_apps_usage_instructions"
        case supportsReasoningSummaryParameter = "supports_reasoning_summary_parameter"
        case defaultReasoningSummary = "default_reasoning_summary"
        case supportVerbosity = "support_verbosity"
        case defaultVerbosity = "default_verbosity"
        case applyPatchToolType = "apply_patch_tool_type"
        case webSearchToolType = "web_search_tool_type"
        case truncationPolicy = "truncation_policy"
        case supportsImageDetailOriginal = "supports_image_detail_original"
        case contextWindow = "context_window"
        case maxContextWindow = "max_context_window"
        case autoCompactTokenLimitValue = "auto_compact_token_limit"
        case compHash = "comp_hash"
        case effectiveContextWindowPercent = "effective_context_window_percent"
        case experimentalSupportedTools = "experimental_supported_tools"
        case inputModalities = "input_modalities"
        case supportsSearchTool = "supports_search_tool"
        case supportsExperimentalContext = "supports_experimental_context"
        case useResponsesLite = "use_responses_lite"
        case supportsReasoningEffortUpdates = "supports_reasoning_effort_updates"
        case nodeReplAutoReviewRequired = "node_repl_auto_review_required"
        case nodeReplDisabled = "node_repl_disabled"
        case autoReviewModelOverride = "auto_review_model_override"
        case modelSpecialty = "model_specialty"
        case toolMode = "tool_mode"
        case multiAgentVersion = "multi_agent_version"
        case multiAgentReasoningEffort = "multi_agent_reasoning_effort"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guardian = try container.decodeIfPresent(GuardianModelPolicy.self, forKey: .guardian)
        slug = try container.decode(String.self, forKey: .slug)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        defaultReasoningLevel = try container.decodeIfPresent(ReasoningEffort.self, forKey: .defaultReasoningLevel)
        supportedReasoningLevels = try container.decode([ReasoningEffortPreset].self, forKey: .supportedReasoningLevels)
        shellType = try container.decode(ConfigShellToolType.self, forKey: .shellType)
        visibility = try container.decode(ModelVisibility.self, forKey: .visibility)
        supportedInApi = try container.decode(Bool.self, forKey: .supportedInApi)
        priority = try container.decode(Int32.self, forKey: .priority)
        additionalSpeedTiers = try container.decodeIfPresent([String].self, forKey: .additionalSpeedTiers) ?? []
        serviceTiers = try container.decodeIfPresent([ModelServiceTier].self, forKey: .serviceTiers) ?? []
        defaultServiceTier = try container.decodeIfPresent(String.self, forKey: .defaultServiceTier)
        availableAccessPrograms = try container.decodeIfPresent(ModelAccessPrograms.self, forKey: .availableAccessPrograms)
        availabilityNux = try container.decodeIfPresent(ModelAvailabilityNux.self, forKey: .availabilityNux)
        upgrade = try container.decodeIfPresent(ModelInfoUpgrade.self, forKey: .upgrade)
        modelMessages = try container.decodeIfPresent(ModelMessages.self, forKey: .modelMessages)
        includeSkillsUsageInstructions = try container.decodeIfPresent(Bool.self, forKey: .includeSkillsUsageInstructions) ?? false
        includePluginUsageInstructions = try container.decodeIfPresent(Bool.self, forKey: .includePluginUsageInstructions) ?? false
        includeAppsUsageInstructions = try container.decodeIfPresent(Bool.self, forKey: .includeAppsUsageInstructions) ?? true
        supportsReasoningSummaryParameter = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoningSummaryParameter) ?? true
        defaultReasoningSummary = try container.decodeIfPresent(ReasoningSummary.self, forKey: .defaultReasoningSummary) ?? .auto
        supportVerbosity = try container.decode(Bool.self, forKey: .supportVerbosity)
        defaultVerbosity = try container.decodeIfPresent(Verbosity.self, forKey: .defaultVerbosity)
        applyPatchToolType = try container.decodeIfPresent(ApplyPatchToolType.self, forKey: .applyPatchToolType)
        webSearchToolType = try container.decodeIfPresent(WebSearchToolType.self, forKey: .webSearchToolType) ?? .text
        truncationPolicy = try container.decode(TruncationPolicyConfig.self, forKey: .truncationPolicy)
        supportsImageDetailOriginal = try container.decodeIfPresent(Bool.self, forKey: .supportsImageDetailOriginal) ?? false
        contextWindow = try container.decodeIfPresent(Int64.self, forKey: .contextWindow)
        maxContextWindow = try container.decodeIfPresent(Int64.self, forKey: .maxContextWindow)
        autoCompactTokenLimitValue = try container.decodeIfPresent(Int64.self, forKey: .autoCompactTokenLimitValue)
        compHash = try container.decodeIfPresent(String.self, forKey: .compHash)
        effectiveContextWindowPercent = try container.decodeIfPresent(Int64.self, forKey: .effectiveContextWindowPercent) ?? 95
        experimentalSupportedTools = try container.decode([String].self, forKey: .experimentalSupportedTools)
        inputModalities = try container.decodeIfPresent([InputModality].self, forKey: .inputModalities) ?? defaultInputModalities()
        usedFallbackModelMetadata = false // skip_serializing, skip_deserializing
        supportsSearchTool = try container.decodeIfPresent(Bool.self, forKey: .supportsSearchTool) ?? false
        supportsExperimentalContext = try container.decodeIfPresent(Bool.self, forKey: .supportsExperimentalContext) ?? false
        useResponsesLite = try container.decodeIfPresent(Bool.self, forKey: .useResponsesLite) ?? false
        supportsReasoningEffortUpdates = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoningEffortUpdates) ?? false
        nodeReplAutoReviewRequired = try container.decodeIfPresent(Bool.self, forKey: .nodeReplAutoReviewRequired) ?? false
        nodeReplDisabled = try container.decodeIfPresent(Bool.self, forKey: .nodeReplDisabled) ?? false
        autoReviewModelOverride = try container.decodeIfPresent(String.self, forKey: .autoReviewModelOverride)
        modelSpecialty = try container.decodeIfPresent(String.self, forKey: .modelSpecialty)
        // deserialize_optional_model_selector: try decoding, treat unknown as nil
        toolMode = try? container.decodeIfPresent(ToolMode.self, forKey: .toolMode)
        multiAgentVersion = try? container.decodeIfPresent(MultiAgentVersion.self, forKey: .multiAgentVersion)
        multiAgentReasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .multiAgentReasoningEffort)
    }
}

extension ModelInfo {
    public func resolvedContextWindow() -> Int64? {
        contextWindow ?? maxContextWindow
    }

    public func usableContextWindow() -> Int64? {
        resolvedContextWindow().map { cw in
            (cw &* effectiveContextWindowPercent) / 100
        }
    }

    public func autoCompactTokenLimit() -> Int64? {
        let contextLimit = resolvedContextWindow().map { ($0 * 9) / 10 }
        if let contextLimit {
            return autoCompactTokenLimitValue.map { min($0, contextLimit) } ?? contextLimit
        }
        return autoCompactTokenLimitValue
    }

    public func supportsServiceTier(_ serviceTier: String) -> Bool {
        serviceTier == ServiceTier.flex.requestValue
            || serviceTiers.contains(where: { $0.id == serviceTier })
    }

    public func serviceTierForRequest(_ serviceTier: String?) -> String? {
        serviceTier.flatMap { tier in
            (tier != serviceTierDefaultRequestValue && supportsServiceTier(tier)) ? tier : nil
        }
    }
}

// MARK: - Reasoning effort resolution (from reasoning_effort.rs)

extension ModelInfo {
    public func resolveReasoningEffort(_ effort: ReasoningEffort) -> ReasoningEffort {
        switch effort {
        case .ultra:
            if let maEffort = multiAgentReasoningEffort,
               maEffort != .ultra,
               supportedReasoningLevels.contains(where: { $0.effort == maEffort }) {
                return maEffort
            }
            if let maxPreset = supportedReasoningLevels.first(where: { $0.effort == .max }) {
                return maxPreset.effort
            }
            if let last = supportedReasoningLevels.last(where: { $0.effort != .ultra }) {
                return last.effort
            }
            return .medium
        case .persistent:
            return .custom("disabled")
        default:
            return effort
        }
    }
}

// MARK: - Guardian on ModelInfo (from guardian.rs)

extension ModelInfo {
    public func guardianReviewMode(_ scope: GuardianScope) -> GuardianReviewMode? {
        guardian.map { $0.reviewMode(scope) }
    }

    public func computerUseReviewRequired() -> Bool {
        guardianReviewMode(.computerUse)
            .map { $0 != .disabled }
            ?? nodeReplAutoReviewRequired
    }
}

// MARK: - ModelMessages & sub-structs

public struct ModelMessages: Codable, Equatable, Sendable {
    public var persistentInstructions: String?
    public var tools: ToolMessages?
    public var instructionsTemplate: String?
    public var instructionsVariables: ModelInstructionsVariables?
    public var approvals: ApprovalMessages?
    public var collaborationModes: CollaborationModeMessages?
    public var autoReview: AutoReviewMessages?
    public var permissions: PermissionMessages?
    public var multiAgent: MultiAgentMessages?
    public var tokenBudget: ModelTokenBudgetConfig?
    public var guardianV2: GuardianV2ModelConfig?
    public var confirmationPolicies: ConfirmationPolicies?

    enum CodingKeys: String, CodingKey {
        case persistentInstructions = "persistent_instructions"
        case tools
        case instructionsTemplate = "instructions_template"
        case instructionsVariables = "instructions_variables"
        case approvals
        case collaborationModes = "collaboration_modes"
        case autoReview = "auto_review"
        case permissions
        case multiAgent = "multi_agent"
        case tokenBudget = "token_budget"
        case guardianV2 = "guardian_v2"
        case confirmationPolicies = "confirmation_policies"
    }

    public init(
        persistentInstructions: String? = nil,
        tools: ToolMessages? = nil,
        instructionsTemplate: String? = nil,
        instructionsVariables: ModelInstructionsVariables? = nil,
        approvals: ApprovalMessages? = nil,
        collaborationModes: CollaborationModeMessages? = nil,
        autoReview: AutoReviewMessages? = nil,
        permissions: PermissionMessages? = nil,
        multiAgent: MultiAgentMessages? = nil,
        tokenBudget: ModelTokenBudgetConfig? = nil,
        guardianV2: GuardianV2ModelConfig? = nil,
        confirmationPolicies: ConfirmationPolicies? = nil
    ) {
        self.persistentInstructions = persistentInstructions
        self.tools = tools
        self.instructionsTemplate = instructionsTemplate
        self.instructionsVariables = instructionsVariables
        self.approvals = approvals
        self.collaborationModes = collaborationModes
        self.autoReview = autoReview
        self.permissions = permissions
        self.multiAgent = multiAgent
        self.tokenBudget = tokenBudget
        self.guardianV2 = guardianV2
        self.confirmationPolicies = confirmationPolicies
    }
}

public struct ConfirmationPolicies: Codable, Equatable, Sendable {
    public var browserUse: String?
    public var computerUse: String?

    enum CodingKeys: String, CodingKey {
        case browserUse = "browser_use"
        case computerUse = "computer_use"
    }
}

public struct ToolMessages: Codable, Equatable, Sendable {
    public var indirectDescriptionPrefixes: IndirectDescriptionPrefixes?
    public var sendUserMessageAsync: ToolMessage?
    public var multiAgent: MultiAgentToolMessages?
    public var codeMode: CodeModeToolMessages?
    public var mcpResources: McpResourceToolMessages?

    enum CodingKeys: String, CodingKey {
        case indirectDescriptionPrefixes = "indirect_description_prefixes"
        case sendUserMessageAsync = "send_user_message_async"
        case multiAgent = "multi_agent"
        case codeMode = "code_mode"
        case mcpResources = "mcp_resources"
    }

    public init(
        indirectDescriptionPrefixes: IndirectDescriptionPrefixes? = nil,
        sendUserMessageAsync: ToolMessage? = nil,
        multiAgent: MultiAgentToolMessages? = nil,
        codeMode: CodeModeToolMessages? = nil,
        mcpResources: McpResourceToolMessages? = nil
    ) {
        self.indirectDescriptionPrefixes = indirectDescriptionPrefixes
        self.sendUserMessageAsync = sendUserMessageAsync
        self.multiAgent = multiAgent
        self.codeMode = codeMode
        self.mcpResources = mcpResources
    }
}

public struct IndirectDescriptionPrefixes: Codable, Equatable, Sendable {
    public var namespaces: [String: String]?
    public var mcpServers: [String: String]?

    enum CodingKeys: String, CodingKey {
        case namespaces
        case mcpServers = "mcp_servers"
    }

    public init(namespaces: [String: String]? = nil, mcpServers: [String: String]? = nil) {
        self.namespaces = namespaces; self.mcpServers = mcpServers
    }
}

public struct ToolMessage: Codable, Equatable, Sendable {
    public var description: String?
    public var parameters: String?

    public init(description: String? = nil, parameters: String? = nil) {
        self.description = description; self.parameters = parameters
    }
}

public struct MultiAgentToolMessages: Codable, Equatable, Sendable {
    public var spawnAgent: ToolMessage?
    public var sendMessage: ToolMessage?
    public var followupTask: ToolMessage?
    public var waitAgent: ToolMessage?
    public var interruptAgent: ToolMessage?
    public var listAgents: ToolMessage?
    public var createChannel: ToolMessage?
    public var getChannels: ToolMessage?
    public var listThreads: ToolMessage?
    public var searchPosts: ToolMessage?
    public var readThread: ToolMessage?
    public var readPost: ToolMessage?
    public var subscribe: ToolMessage?
    public var unsubscribe: ToolMessage?
    public var post: ToolMessage?

    enum CodingKeys: String, CodingKey {
        case spawnAgent = "spawn_agent"
        case sendMessage = "send_message"
        case followupTask = "followup_task"
        case waitAgent = "wait_agent"
        case interruptAgent = "interrupt_agent"
        case listAgents = "list_agents"
        case createChannel = "create_channel"
        case getChannels = "get_channels"
        case listThreads = "list_threads"
        case searchPosts = "search_posts"
        case readThread = "read_thread"
        case readPost = "read_post"
        case subscribe, unsubscribe, post
    }

    public init(
        spawnAgent: ToolMessage? = nil, sendMessage: ToolMessage? = nil,
        followupTask: ToolMessage? = nil, waitAgent: ToolMessage? = nil,
        interruptAgent: ToolMessage? = nil, listAgents: ToolMessage? = nil,
        createChannel: ToolMessage? = nil, getChannels: ToolMessage? = nil,
        listThreads: ToolMessage? = nil, searchPosts: ToolMessage? = nil,
        readThread: ToolMessage? = nil, readPost: ToolMessage? = nil,
        subscribe: ToolMessage? = nil, unsubscribe: ToolMessage? = nil,
        post: ToolMessage? = nil
    ) {
        self.spawnAgent = spawnAgent; self.sendMessage = sendMessage
        self.followupTask = followupTask; self.waitAgent = waitAgent
        self.interruptAgent = interruptAgent; self.listAgents = listAgents
        self.createChannel = createChannel; self.getChannels = getChannels
        self.listThreads = listThreads; self.searchPosts = searchPosts
        self.readThread = readThread; self.readPost = readPost
        self.subscribe = subscribe; self.unsubscribe = unsubscribe
        self.post = post
    }

    public func byName(_ name: String) -> ToolMessage? {
        switch name {
        case "spawn_agent": return spawnAgent
        case "send_message": return sendMessage
        case "followup_task": return followupTask
        case "wait_agent": return waitAgent
        case "interrupt_agent": return interruptAgent
        case "list_agents": return listAgents
        case "create_channel": return createChannel
        case "get_channels": return getChannels
        case "list_threads": return listThreads
        case "search_posts": return searchPosts
        case "read_thread": return readThread
        case "read_post": return readPost
        case "subscribe": return subscribe
        case "unsubscribe": return unsubscribe
        case "post": return post
        default: return nil
        }
    }
}

public struct McpResourceToolMessages: Codable, Equatable, Sendable {
    public var listMcpResources: ToolMessage?
    public var listMcpResourceTemplates: ToolMessage?
    public var readMcpResource: ToolMessage?

    enum CodingKeys: String, CodingKey {
        case listMcpResources = "list_mcp_resources"
        case listMcpResourceTemplates = "list_mcp_resource_templates"
        case readMcpResource = "read_mcp_resource"
    }
}

public struct CodeModeToolMessages: Codable, Equatable, Sendable {
    public var exec: ToolMessage?
    public var wait: ToolMessage?
    public var deferredNestedToolsGuidance: String?
    public var mcpTypescriptPreamble: String?

    enum CodingKeys: String, CodingKey {
        case exec, wait
        case deferredNestedToolsGuidance = "deferred_nested_tools_guidance"
        case mcpTypescriptPreamble = "mcp_typescript_preamble"
    }

    public init(
        exec: ToolMessage? = nil, wait: ToolMessage? = nil,
        deferredNestedToolsGuidance: String? = nil, mcpTypescriptPreamble: String? = nil
    ) {
        self.exec = exec; self.wait = wait
        self.deferredNestedToolsGuidance = deferredNestedToolsGuidance
        self.mcpTypescriptPreamble = mcpTypescriptPreamble
    }
}

public struct ModelTokenBudgetConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var useHistoryNotesExtension: Bool
    public var reminderThresholdTokens: Int64
    public var reminderMessageTemplate: String
    public var guidanceMessage: String
    public var autoCompactFallbackPrompt: String
    public var autoCompactFallbackBufferTokens: Int64

    enum CodingKeys: String, CodingKey {
        case enabled
        case useHistoryNotesExtension = "use_history_notes_extension"
        case reminderThresholdTokens = "reminder_threshold_tokens"
        case reminderMessageTemplate = "reminder_message_template"
        case guidanceMessage = "guidance_message"
        case autoCompactFallbackPrompt = "auto_compact_fallback_prompt"
        case autoCompactFallbackBufferTokens = "auto_compact_fallback_buffer_tokens"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        useHistoryNotesExtension = try container.decodeIfPresent(Bool.self, forKey: .useHistoryNotesExtension) ?? false
        reminderThresholdTokens = try container.decode(Int64.self, forKey: .reminderThresholdTokens)
        reminderMessageTemplate = try container.decode(String.self, forKey: .reminderMessageTemplate)
        guidanceMessage = try container.decode(String.self, forKey: .guidanceMessage)
        autoCompactFallbackPrompt = try container.decode(String.self, forKey: .autoCompactFallbackPrompt)
        autoCompactFallbackBufferTokens = try container.decode(Int64.self, forKey: .autoCompactFallbackBufferTokens)
    }
}

public struct ApprovalMessages: Codable, Equatable, Sendable {
    public var onRequest: String?
    public var onRequestAutoReview: String?
    public var never: String?
    public var unlessTrusted: String?

    enum CodingKeys: String, CodingKey {
        case onRequest = "on_request"
        case onRequestAutoReview = "on_request_auto_review"
        case never
        case unlessTrusted = "unless_trusted"
    }
}

public struct CollaborationModeMessages: Codable, Equatable, Sendable {
    public var `default`: String?
    public var plan: String?
}

public struct AutoReviewMessages: Codable, Equatable, Sendable {
    public var policy: String?
    public var policyTemplate: String?
    public var nodeReplPolicy: String?
    public var rejectionInstructions: String?
    public var timeoutInstructions: String?

    enum CodingKeys: String, CodingKey {
        case policy
        case policyTemplate = "policy_template"
        case nodeReplPolicy = "node_repl_policy"
        case rejectionInstructions = "rejection_instructions"
        case timeoutInstructions = "timeout_instructions"
    }
}

public struct PermissionMessages: Codable, Equatable, Sendable {
    public var dangerFullAccess: String?
    public var workspaceWrite: String?
    public var readOnly: String?

    enum CodingKeys: String, CodingKey {
        case dangerFullAccess = "danger_full_access"
        case workspaceWrite = "workspace_write"
        case readOnly = "read_only"
    }
}

public struct MultiAgentMessages: Codable, Equatable, Sendable {
    public var role: MultiAgentRoleMessages?
    public var mode: MultiAgentModeMessages?

    public init(role: MultiAgentRoleMessages? = nil, mode: MultiAgentModeMessages? = nil) {
        self.role = role; self.mode = mode
    }
}

public struct MultiAgentRoleMessages: Codable, Equatable, Sendable {
    public var root: String?
    public var subagent: String?
}

public struct MultiAgentModeMessages: Codable, Equatable, Sendable {
    public var explicit: String?
    public var proactive: String?
    public var hintText: String?

    enum CodingKeys: String, CodingKey {
        case explicit, proactive
        case hintText = "hint_text"
    }
}

public struct ModelInstructionsVariables: Codable, Equatable, Sendable {
    public var personalityDefault: String?
    public var personalityFriendly: String?
    public var personalityPragmatic: String?

    enum CodingKeys: String, CodingKey {
        case personalityDefault = "personality_default"
        case personalityFriendly = "personality_friendly"
        case personalityPragmatic = "personality_pragmatic"
    }
}

// MARK: - ModelInfoUpgrade

public struct ModelInfoUpgrade: Codable, Equatable, Sendable {
    public var model: String
    public var migrationMarkdown: String
    public var retirementAt: Date?

    enum CodingKeys: String, CodingKey {
        case model
        case migrationMarkdown = "migration_markdown"
        case retirementAt = "retirement_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        migrationMarkdown = try container.decode(String.self, forKey: .migrationMarkdown)
        retirementAt = try decodeOptionalRFC3339(container: container, forKey: .retirementAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(migrationMarkdown, forKey: .migrationMarkdown)
        try encodeOptionalRFC3339(retirementAt, container: &container, forKey: .retirementAt)
    }

    public init(model: String, migrationMarkdown: String, retirementAt: Date? = nil) {
        self.model = model; self.migrationMarkdown = migrationMarkdown
        self.retirementAt = retirementAt
    }
}

extension ModelInfoUpgrade {
    public init(from upgrade: ModelUpgrade) {
        self.init(
            model: upgrade.id,
            migrationMarkdown: upgrade.migrationMarkdown ?? "",
            retirementAt: upgrade.retirementAt
        )
    }
}

// MARK: - ModelInfo → ModelPreset conversion

extension ModelPreset {
    public init(from info: ModelInfo) {
        self.init()
        id = info.slug
        model = info.slug
        displayName = info.displayName
        description = info.description ?? ""
        modelSpecialty = info.modelSpecialty
        defaultReasoningEffort = info.defaultReasoningLevel ?? .none
        supportedReasoningEfforts = info.supportedReasoningLevels
        supportsPersonality = false
        additionalSpeedTiers = info.additionalSpeedTiers
        serviceTiers = info.serviceTiers
        defaultServiceTier = info.defaultServiceTier
        availableAccessPrograms = info.availableAccessPrograms
        isDefault = false
        upgrade = info.upgrade.map { u in
            ModelUpgrade(
                id: u.model, migrationConfigKey: info.slug,
                modelLink: nil, upgradeCopy: nil,
                migrationMarkdown: u.migrationMarkdown,
                retirementAt: u.retirementAt
            )
        }
        showInPicker = info.visibility == .list
        multiAgentVersion = info.multiAgentVersion
        availabilityNux = info.availabilityNux
        supportedInApi = info.supportedInApi
        inputModalities = info.inputModalities
    }

    fileprivate init() {
        id = ""; model = ""; displayName = ""; description = ""
        defaultReasoningEffort = .medium; supportedReasoningEfforts = []
        supportsPersonality = false; additionalSpeedTiers = []; serviceTiers = []
        isDefault = false; showInPicker = false; supportedInApi = false
        inputModalities = defaultInputModalities()
    }
}

// MARK: - ModelsResponse

public struct ModelsResponse: Codable, Equatable, Sendable {
    public var models: [ModelInfo]

    public init(models: [ModelInfo] = []) { self.models = models }
}

// MARK: - RFC-3339 date helpers

private let rfc3339Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let rfc3339FormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func decodeOptionalRFC3339<K: CodingKey>(
    container: KeyedDecodingContainer<K>, forKey key: K
) throws -> Date? {
    guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
    return rfc3339Formatter.date(from: raw) ?? rfc3339FormatterNoFrac.date(from: raw)
}

func encodeOptionalRFC3339<K: CodingKey>(
    _ date: Date?, container: inout KeyedEncodingContainer<K>, forKey key: K
) throws {
    guard let date else {
        try container.encodeNil(forKey: key)
        return
    }
    try container.encode(rfc3339FormatterNoFrac.string(from: date), forKey: key)
}
