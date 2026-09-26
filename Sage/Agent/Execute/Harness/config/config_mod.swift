//
//  config_mod.swift
//  Sage
//
//  Port of codex-rs/core/src/config/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Config type shape and merge/priority fields. Loaders read Sage
//  Settings rather than Codex TOML layers (plan §10.4).
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
        startupWarnings: [String] = []
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
