//
//  service.swift
//  Sage
//
//  Port of codex-rs/core/src/state/service.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Phase 6/9 services (ModelClient, AuthManager, plugins) stay optional.
//  MCP catalog + handler cache names feed assembleToolRouter.
//  Apps enablement / policy, onMcpCall, and onSageToolCall are the live
//  binding seams. `parallelAdmission` is rust `parallel_execution`;
//  `turnDiffTracker` is rust's per-turn apply_patch diff;
//  `approvalStore` is the HUD SessionToolAllowlist cache when attached.
//  Registry Pre/PostToolUse reads `hookProjectRoot` + activated skills.
//  `afterAgentHooks` is rust `Hooks.after_agent` (legacy notify).
//

import CodexCore
import CodexExecPolicy
import CodexHooks
import CodexProtocol
import Foundation

final class SessionServices: @unchecked Sendable {
    var mcpRuntime: SessionMcpRuntime
    var execPolicy: Policy?
    var showRawAgentReasoning: Bool
    var selectedCapabilityRoots: [String]
    var executedToolCalls: ExecutedToolCalls
    var modelClient: CodexCore.ModelClient?
    var availablePlugins: [PluginCapabilitySummary]
    var availableConnectors: [AppInfo]
    var mcpTools: [PluginToolInfo]
    var modelVisibleMcpToolNames: [String]
    var mcpVisibleTools: [McpVisibleTool]
    var mcpHandlerCache: McpHandlerCache
    var mcpBindingID: UInt64
    var appsEnabled: Bool
    var appsPolicy: AppsConfig?
    var onMcpCall: (@Sendable (String, String, HarnessJSON) async -> String?)?
    /// Sage execute tools (list_directory, apply_patch, …). Wired by RegularTask.
    var sageToolNames: [String]
    /// Full Responses tool schemas for the prompt `runTurn` builds.
    /// Nil keeps the name-only specs from the tool router.
    var sageResponsesTools: [CodexProtocol.JSONValue]?
    var onSageToolCall: (@Sendable (String, String, String) async -> String?)?
    /// rust `SessionServices.parallel_execution` RWLock.
    var parallelAdmission: ParallelAdmission
    /// rust `TurnDiffTracker` for this execute turn.
    var turnDiffTracker: TurnDiffTracker
    /// HUD `SessionToolAllowlist.approvalStore` when RegularTask attaches.
    var approvalStore: ApprovalStore?
    /// `.sage/hooks.json` root for registry Pre/PostToolUse.
    var hookProjectRoot: URL?
    /// Activated skill records so skill `hooks.json` matches live Execute.
    var hookActivatedSkills: [SkillRecord]
    /// rust `Hooks.after_agent` (legacy `notify` argv). No ClaudeHooksEngine.
    var afterAgentHooks: [Hook]
    var skillsLookup: SessionSkillsLookup
    var turnInputContributors: [any TurnInputContributor]

    init(
        mcpRuntime: SessionMcpRuntime = SessionMcpRuntime(),
        execPolicy: Policy? = nil,
        showRawAgentReasoning: Bool = false,
        selectedCapabilityRoots: [String] = [],
        modelClient: CodexCore.ModelClient? = nil,
        availablePlugins: [PluginCapabilitySummary] = [],
        availableConnectors: [AppInfo] = [],
        mcpTools: [PluginToolInfo] = [],
        modelVisibleMcpToolNames: [String] = [],
        mcpVisibleTools: [McpVisibleTool] = [],
        mcpHandlerCache: McpHandlerCache = McpHandlerCache(),
        mcpBindingID: UInt64 = 1,
        appsEnabled: Bool = true,
        appsPolicy: AppsConfig? = nil,
        onMcpCall: (@Sendable (String, String, HarnessJSON) async -> String?)? = nil,
        sageToolNames: [String] = [],
        sageResponsesTools: [CodexProtocol.JSONValue]? = nil,
        onSageToolCall: (@Sendable (String, String, String) async -> String?)? = nil,
        parallelAdmission: ParallelAdmission = ParallelAdmission(),
        turnDiffTracker: TurnDiffTracker = TurnDiffTracker(),
        approvalStore: ApprovalStore? = nil,
        hookProjectRoot: URL? = nil,
        hookActivatedSkills: [SkillRecord] = [],
        afterAgentHooks: [Hook] = [],
        skillsLookup: SessionSkillsLookup = SessionSkillsLookup(),
        turnInputContributors: [any TurnInputContributor] = []
    ) {
        self.mcpRuntime = mcpRuntime
        self.execPolicy = execPolicy
        self.showRawAgentReasoning = showRawAgentReasoning
        self.selectedCapabilityRoots = selectedCapabilityRoots
        self.executedToolCalls = ExecutedToolCalls()
        self.modelClient = modelClient
        self.availablePlugins = availablePlugins
        self.availableConnectors = availableConnectors
        self.mcpTools = mcpTools
        self.modelVisibleMcpToolNames = modelVisibleMcpToolNames
        self.mcpVisibleTools = mcpVisibleTools
        self.mcpHandlerCache = mcpHandlerCache
        self.mcpBindingID = mcpBindingID
        self.appsEnabled = appsEnabled
        self.appsPolicy = appsPolicy
        self.onMcpCall = onMcpCall
        self.sageToolNames = sageToolNames
        self.sageResponsesTools = sageResponsesTools
        self.onSageToolCall = onSageToolCall
        self.parallelAdmission = parallelAdmission
        self.turnDiffTracker = turnDiffTracker
        self.approvalStore = approvalStore
        self.hookProjectRoot = hookProjectRoot
        self.hookActivatedSkills = hookActivatedSkills
        self.afterAgentHooks = afterAgentHooks
        self.skillsLookup = skillsLookup
        self.turnInputContributors = turnInputContributors
    }
}

protocol TurnInputContributor: AnyObject {
    func contribute(userInput: [UserInput], turnId: String) async -> [ResponseItem]
}
