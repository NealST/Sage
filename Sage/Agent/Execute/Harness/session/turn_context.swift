//
//  turn_context.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Turn-scoped settings, sessionSource, and model snapshot used by
//  `runTurn`. Start options (schema, cyber program, trigger, parent and
//  root turn ids, service tier) are captured when the turn is admitted.
//  `dynamicTools` is copied from the session configuration at admission.
//  `TurnEnvironment` carries workspace roots and temporary directories
//  for `request_permissions`. Shell snapshot futures and plugin metrics wait.
//

import CodexCore
import CodexProtocol
import Foundation

struct TurnEnvironment: Sendable {
    var environmentId: String
    var cwd: String
    var userHomeDir: String?
    var executorPlatformOS: String?
    /// Empty means the environment did not configure roots. The permission
    /// policy context then uses `cwd`.
    var workspaceRoots: [String]
    /// `nil` means the executor did not report temporary directories.
    var temporaryDirectories: [String]?

    init(
        environmentId: String = "local",
        cwd: String = FileManager.default.currentDirectoryPath,
        userHomeDir: String? = NSHomeDirectory(),
        executorPlatformOS: String? = "macos",
        workspaceRoots: [String] = [],
        temporaryDirectories: [String]? = nil
    ) {
        self.environmentId = environmentId
        self.cwd = cwd
        self.userHomeDir = userHomeDir
        self.executorPlatformOS = executorPlatformOS
        self.workspaceRoots = workspaceRoots
        self.temporaryDirectories = temporaryDirectories
    }
}

/// rust `EnvironmentInfo::local_temporary_directories` for a local executor.
func localTemporaryDirectoryPaths() -> [String] {
    #if os(Windows)
    let names = ["TEMP", "TMP"]
    #else
    let names = ["TMPDIR"]
    #endif
    var directories: [String] = []
    for name in names {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { continue }
        if !directories.contains(value) {
            directories.append(value)
        }
    }
    return directories
}

final class TurnContext: @unchecked Sendable {
    var subId: String
    var sessionId: SessionId
    var threadId: ThreadId
    var cwd: String
    var model: String
    var modelCompHash: String?
    var modelContextWindow: Int64?
    var effectiveContextWindowPercent: Int64
    var autoCompactTokenLimitValue: Int64?
    var sessionSource: SessionSource
    var config: Config
    var approvalPolicy: CodexProtocol.AskForApproval
    var sandboxPolicy: SandboxPolicy
    var permissionProfile: PermissionProfile
    var disabledPluginIds: [String]
    var collaborationMode: CollaborationMode?
    var environment: TurnEnvironment
    var finalOutputJsonSchema: CodexProtocol.JSONValue?
    var cyberAccessProgram: CyberAccessProgram?
    var realtimeActive: Bool
    var nextStepSettings: StepSettings
    var terminalError: CodexErr?
    var turnTrigger: String?
    var parentTurnId: String?
    var rootTurnId: String?
    var responsesapiClientMetadata: [String: String]?
    var initiatingAgentPath: AgentPath?
    /// Catalog snapshot used by tool planning. Absent turns use `minimalModelInfo`.
    var catalogModelInfo: ModelInfo?
    /// Copied from the session configuration when the turn is admitted.
    var dynamicTools: [DynamicToolSpec]

    init(
        subId: String = UUID().uuidString,
        sessionId: SessionId = SessionId(),
        threadId: ThreadId = ThreadId(),
        cwd: String = FileManager.default.currentDirectoryPath,
        model: String = "gpt-5",
        modelCompHash: String? = nil,
        modelContextWindow: Int64? = nil,
        effectiveContextWindowPercent: Int64 = 95,
        autoCompactTokenLimitValue: Int64? = nil,
        sessionSource: SessionSource = .cli,
        config: Config = Config(),
        approvalPolicy: CodexProtocol.AskForApproval = CodexProtocol.AskForApproval.onRequest,
        sandboxPolicy: SandboxPolicy = .readOnly(networkAccess: false),
        permissionProfile: PermissionProfile = .readOnly(),
        disabledPluginIds: [String] = [],
        collaborationMode: CollaborationMode? = nil,
        environment: TurnEnvironment = TurnEnvironment(),
        finalOutputJsonSchema: CodexProtocol.JSONValue? = nil,
        cyberAccessProgram: CyberAccessProgram? = nil,
        realtimeActive: Bool = false,
        nextStepSettings: StepSettings = StepSettings(),
        terminalError: CodexErr? = nil,
        turnTrigger: String? = nil,
        parentTurnId: String? = nil,
        rootTurnId: String? = nil,
        responsesapiClientMetadata: [String: String]? = nil,
        initiatingAgentPath: AgentPath? = nil,
        catalogModelInfo: ModelInfo? = nil,
        dynamicTools: [DynamicToolSpec] = []
    ) {
        self.subId = subId
        self.sessionId = sessionId
        self.threadId = threadId
        self.cwd = cwd
        self.model = model
        self.modelCompHash = modelCompHash
        self.modelContextWindow = modelContextWindow
        self.effectiveContextWindowPercent = effectiveContextWindowPercent
        self.autoCompactTokenLimitValue = autoCompactTokenLimitValue
        self.sessionSource = sessionSource
        self.config = config
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.permissionProfile = permissionProfile
        self.disabledPluginIds = disabledPluginIds
        self.collaborationMode = collaborationMode
        self.environment = environment
        self.finalOutputJsonSchema = finalOutputJsonSchema
        self.cyberAccessProgram = cyberAccessProgram
        self.realtimeActive = realtimeActive
        self.nextStepSettings = nextStepSettings
        self.terminalError = terminalError
        self.turnTrigger = turnTrigger
        self.parentTurnId = parentTurnId
        self.rootTurnId = rootTurnId
        self.responsesapiClientMetadata = responsesapiClientMetadata
        self.initiatingAgentPath = initiatingAgentPath
        self.catalogModelInfo = catalogModelInfo
        self.dynamicTools = dynamicTools
    }

    func collaborationModeValue() -> CollaborationMode? {
        collaborationMode
    }

    func mode() -> ModeKind {
        collaborationMode?.mode ?? .default
    }

    func captureCurrentModelInfo() -> TurnModelSnapshot {
        TurnModelSnapshot(
            slug: model,
            compHash: modelCompHash,
            contextWindow: modelContextWindow,
            effectiveContextWindowPercent: effectiveContextWindowPercent,
            autoCompactTokenLimitValue: autoCompactTokenLimitValue
        )
    }

    func resolvedContextWindow() -> Int64? {
        modelContextWindow ?? config.modelContextWindow
    }

    func usableContextWindow() -> Int64? {
        resolvedContextWindow().map { ($0 &* effectiveContextWindowPercent) / 100 }
    }

    func modelInfoValue() -> ModelInfo {
        catalogModelInfo ?? minimalModelInfo(slug: model)
    }

    func autoCompactTokenLimit() -> Int64? {
        let contextLimit = resolvedContextWindow().map { ($0 * 9) / 10 }
        if let contextLimit {
            return autoCompactTokenLimitValue.map { min($0, contextLimit) } ?? contextLimit
        }
        return autoCompactTokenLimitValue ?? config.modelAutoCompactTokenLimit
    }
}

struct TurnModelSnapshot: Equatable, Sendable {
    var slug: String
    var compHash: String?
    var contextWindow: Int64?
    var effectiveContextWindowPercent: Int64
    var autoCompactTokenLimitValue: Int64?

    init(
        slug: String,
        compHash: String? = nil,
        contextWindow: Int64? = nil,
        effectiveContextWindowPercent: Int64 = 95,
        autoCompactTokenLimitValue: Int64? = nil
    ) {
        self.slug = slug
        self.compHash = compHash
        self.contextWindow = contextWindow
        self.effectiveContextWindowPercent = effectiveContextWindowPercent
        self.autoCompactTokenLimitValue = autoCompactTokenLimitValue
    }
}

struct NewTurnContextOptions: Sendable {
    var subId: String?
    var model: String?
    var start: TurnStartOptions
    var responsesapiClientMetadata: [String: String]?
    var initiatingAgentPath: AgentPath?

    init(
        subId: String? = nil,
        model: String? = nil,
        start: TurnStartOptions = TurnStartOptions(),
        responsesapiClientMetadata: [String: String]? = nil,
        initiatingAgentPath: AgentPath? = nil
    ) {
        self.subId = subId
        self.model = model
        self.start = start
        self.responsesapiClientMetadata = responsesapiClientMetadata
        self.initiatingAgentPath = initiatingAgentPath
    }
}

func initiatingAgentPath(in input: [SessionTurnInput], parentTurnId: String?) -> AgentPath? {
    guard parentTurnId != nil else { return nil }
    for item in input {
        if case .interAgentCommunication(let communication) = item, communication.triggerTurn {
            return communication.author
        }
    }
    return nil
}
