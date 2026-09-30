//
//  config_mod.swift
//  Sage
//
//  Port of codex-rs/core/src/config/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Config type shape, TokenBudgetConfig, and merge/priority fields.
//  Loaders read Sage Settings rather than Codex TOML layers (plan §10.4).
//

import CodexCore
import CodexProtocol
import Foundation

struct CurrentTimeReminderConfig: Equatable, Sendable {
    var sleepTool: Bool
    var intervalSeconds: UInt64
    var clockSource: CurrentTimeSource
    var deliveryMode: CurrentTimeReminderDeliveryMode

    init(
        sleepTool: Bool = false,
        intervalSeconds: UInt64 = 1,
        clockSource: CurrentTimeSource = .system,
        deliveryMode: CurrentTimeReminderDeliveryMode = .anyInference
    ) {
        self.sleepTool = sleepTool
        self.intervalSeconds = intervalSeconds
        self.clockSource = clockSource
        self.deliveryMode = deliveryMode
    }
}

let tokenBudgetReminderTemplateMaxBytes = 2000
let tokenBudgetGuidanceMessageMaxBytes = 2000
let autoCompactFallbackPromptMaxBytes = 2000
let tokenBudgetDefaultReminderTemplate =
    "Context is filling. Prefer compacting or finishing the current task before adding more tool output."

enum TokenBudgetConfigError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

/// Codex `TokenBudgetConfig`. Buffer tokens are reserved only when a
/// fallback prompt is present.
struct TokenBudgetConfig: Equatable, Sendable {
    var useHistoryNotesExtension: Bool
    var reminderThresholdTokens: Int64?
    var reminderMessageTemplate: String
    var guidanceMessage: String?
    var autoCompactFallbackPrompt: String?
    var autoCompactFallbackBufferTokens: Int64?

    init(
        useHistoryNotesExtension: Bool = false,
        reminderThresholdTokens: Int64? = nil,
        reminderMessageTemplate: String = tokenBudgetDefaultReminderTemplate,
        guidanceMessage: String? = nil,
        autoCompactFallbackPrompt: String? = nil,
        autoCompactFallbackBufferTokens: Int64? = nil
    ) {
        self.useHistoryNotesExtension = useHistoryNotesExtension
        self.reminderThresholdTokens = reminderThresholdTokens
        self.reminderMessageTemplate = reminderMessageTemplate
        self.guidanceMessage = guidanceMessage
        self.autoCompactFallbackPrompt = autoCompactFallbackPrompt
        self.autoCompactFallbackBufferTokens = autoCompactFallbackBufferTokens
    }

    func validate() -> Result<Void, TokenBudgetConfigError> {
        if let tokens = reminderThresholdTokens, tokens <= 0 {
            return .failure(.invalid(
                "features.token_budget.reminder_threshold_tokens must be positive"
            ))
        }
        if reminderMessageTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.invalid(
                "features.token_budget.reminder_message_template must not be empty"
            ))
        }
        if reminderMessageTemplate.utf8.count > tokenBudgetReminderTemplateMaxBytes {
            return .failure(.invalid(
                "features.token_budget.reminder_message_template must not exceed \(tokenBudgetReminderTemplateMaxBytes) bytes"
            ))
        }
        if let guidance = guidanceMessage, guidance.utf8.count > tokenBudgetGuidanceMessageMaxBytes {
            return .failure(.invalid(
                "features.token_budget.guidance_message must not exceed \(tokenBudgetGuidanceMessageMaxBytes) bytes"
            ))
        }
        if let prompt = autoCompactFallbackPrompt, prompt.utf8.count > autoCompactFallbackPromptMaxBytes {
            return .failure(.invalid(
                "features.token_budget.auto_compact_fallback_prompt must not exceed \(autoCompactFallbackPromptMaxBytes) bytes"
            ))
        }
        if autoCompactFallbackPrompt != nil, autoCompactFallbackBufferTokens == nil {
            return .failure(.invalid(
                "features.token_budget.auto_compact_fallback_buffer_tokens is required when auto_compact_fallback_prompt is set"
            ))
        }
        if let tokens = autoCompactFallbackBufferTokens, tokens <= 0 {
            return .failure(.invalid(
                "features.token_budget.auto_compact_fallback_buffer_tokens must be positive"
            ))
        }
        return .success(())
    }

    /// Codex `TokenBudgetConfig::fallback_buffer_tokens`.
    func fallbackBufferTokens() -> Int64 {
        autoCompactFallbackPrompt == nil ? 0 : (autoCompactFallbackBufferTokens ?? 0)
    }
}

struct ConfigOverrides: Equatable, Sendable {
    var model: String?
    var reviewModel: String?
    var cwd: String?
    var approvalPolicy: CodexProtocol.AskForApproval?
    var sandboxMode: SandboxMode?
    var permissionProfile: PermissionProfile?
    var modelProvider: String?
    var baseInstructions: String?
    var developerInstructions: String?
    var showRawAgentReasoning: Bool?

    init(
        model: String? = nil,
        reviewModel: String? = nil,
        cwd: String? = nil,
        approvalPolicy: CodexProtocol.AskForApproval? = nil,
        sandboxMode: SandboxMode? = nil,
        permissionProfile: PermissionProfile? = nil,
        modelProvider: String? = nil,
        baseInstructions: String? = nil,
        developerInstructions: String? = nil,
        showRawAgentReasoning: Bool? = nil
    ) {
        self.model = model
        self.reviewModel = reviewModel
        self.cwd = cwd
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
        self.permissionProfile = permissionProfile
        self.modelProvider = modelProvider
        self.baseInstructions = baseInstructions
        self.developerInstructions = developerInstructions
        self.showRawAgentReasoning = showRawAgentReasoning
    }
}

struct Config: Equatable, Sendable {
    var model: String?
    var reviewModel: String?
    var modelContextWindow: Int64?
    var modelAutoCompactTokenLimit: Int64?
    var modelAutoCompactTokenLimitScope: AutoCompactTokenLimitScope
    var modelPostTurnCompactThresholdPercent: UInt8
    var modelProviderId: String
    var hideAgentReasoning: Bool
    var showRawAgentReasoning: Bool
    var baseInstructions: String?
    var baseInstructionsProvenance: BaseInstructionsProvenance?
    var developerInstructions: String?
    var cwd: String
    var approvalPolicy: CodexProtocol.AskForApproval
    var features: Features
    var currentTimeReminder: CurrentTimeReminderConfig?
    var agentInterruptMessageEnabled: Bool
    var permissions: Permissions
    var startupWarnings: [String]
    var tokenBudget: TokenBudgetConfig?

    init(
        model: String? = nil,
        reviewModel: String? = nil,
        modelContextWindow: Int64? = nil,
        modelAutoCompactTokenLimit: Int64? = nil,
        modelAutoCompactTokenLimitScope: AutoCompactTokenLimitScope = .total,
        modelPostTurnCompactThresholdPercent: UInt8 = 90,
        modelProviderId: String = "openai",
        hideAgentReasoning: Bool = false,
        showRawAgentReasoning: Bool = false,
        baseInstructions: String? = nil,
        baseInstructionsProvenance: BaseInstructionsProvenance? = nil,
        developerInstructions: String? = nil,
        cwd: String = FileManager.default.currentDirectoryPath,
        approvalPolicy: CodexProtocol.AskForApproval = CodexProtocol.AskForApproval.onRequest,
        features: Features = Features(),
        currentTimeReminder: CurrentTimeReminderConfig? = nil,
        agentInterruptMessageEnabled: Bool = true,
        permissions: Permissions = Permissions(),
        startupWarnings: [String] = [],
        tokenBudget: TokenBudgetConfig? = nil
    ) {
        self.model = model
        self.reviewModel = reviewModel
        self.modelContextWindow = modelContextWindow
        self.modelAutoCompactTokenLimit = modelAutoCompactTokenLimit
        self.modelAutoCompactTokenLimitScope = modelAutoCompactTokenLimitScope
        self.modelPostTurnCompactThresholdPercent = modelPostTurnCompactThresholdPercent
        self.modelProviderId = modelProviderId
        self.hideAgentReasoning = hideAgentReasoning
        self.showRawAgentReasoning = showRawAgentReasoning
        self.baseInstructions = baseInstructions
        self.baseInstructionsProvenance = baseInstructionsProvenance
        self.developerInstructions = developerInstructions
        self.cwd = cwd
        self.approvalPolicy = approvalPolicy
        self.features = features
        self.currentTimeReminder = currentTimeReminder
        self.agentInterruptMessageEnabled = agentInterruptMessageEnabled
        self.permissions = permissions
        self.startupWarnings = startupWarnings
        self.tokenBudget = tokenBudget
    }

    func applying(_ overrides: ConfigOverrides) -> Config {
        var copy = self
        if let model = overrides.model { copy.model = model }
        if let reviewModel = overrides.reviewModel { copy.reviewModel = reviewModel }
        if let cwd = overrides.cwd { copy.cwd = cwd }
        if let approvalPolicy = overrides.approvalPolicy { copy.approvalPolicy = approvalPolicy }
        if let baseInstructions = overrides.baseInstructions { copy.baseInstructions = baseInstructions }
        if let developerInstructions = overrides.developerInstructions {
            copy.developerInstructions = developerInstructions
        }
        if let showRaw = overrides.showRawAgentReasoning { copy.showRawAgentReasoning = showRaw }
        return copy
    }
}
