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

import SageCore
import SageExecPolicy
import SageHistory
import SageHooks
import SageProtocol
import SageThreadStore
import Foundation

final class SessionServices: @unchecked Sendable {
    var mcpRuntime: SessionMcpRuntime
    /// rust `SessionServices.elicitations`. Counts in-flight MCP elicitations.
    var elicitations = ElicitationService()
    var execPolicy: Policy?
    var showRawAgentReasoning: Bool
    var selectedCapabilityRoots: [String]
    var executedToolCalls: ExecutedToolCalls
    var modelClient: SageCore.ModelClient?
    /// rust `thread_extension_data` `ExhaustedResponseRetry`. Guardian
    /// reads `retryAt`; the turn loop does not wait on it.
    var exhaustedResponseRetry: ExhaustedResponseRetry?
    /// rust `thread_extension_data` `SleepItem`. The sleep tool is not
    /// loaded; a set flag lets queue-only mailbox mail wake a turn.
    var outstandingDurableSleep = false
    /// Stand-in for `list_live_agent_subtree_thread_ids`. The root counts
    /// as one. A larger count refuses root-turn suspension.
    var liveAgentSubtreeCount = 1
    /// rust `unified_exec_manager`. Background terminals for this thread.
    var unifiedExecManager = UnifiedExecProcessManager()
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
    /// Prepared catalog calls. Live Execute points this at `invokeHarnessTool`,
    /// which reaches `MCPStdioClient` through `CapabilityStore`.
    var mcpToolTransport: (@Sendable (McpToolCallRequest) async throws -> CallToolResult)?
    /// Connect enabled MCP servers that are not already running.
    var ensureMcpConnected: (@Sendable () async -> Void)?
    /// Drop and reconnect enabled MCP servers after `reconnect_pending`.
    var reconnectMcp: (@Sendable () async -> Void)?
    /// Disconnect servers that a publish dropped. Names are connection keys.
    var disconnectMcp: (@Sendable ([String]) async -> Void)?
    /// Append rollout items. Nil means this session has no live writer.
    var persistRolloutItems: (@Sendable ([RolloutItem]) async throws -> Void)?
    /// rust `SessionServices.live_thread`. Nil means persistence is disabled.
    var liveThread: LiveThread?
    /// Sage execute tools (list_directory, apply_patch, …) with their real
    /// JSON Schemas. Wired by RegularTask; `assembleToolRouter` registers
    /// them so the router is the single tool assembly point.
    var sageToolSpecs: [SageToolSpec]
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
    /// Live Execute attaches the parent ThreadManager so spawn/wait/interrupt
    /// can start child SageThreads without opening a second parent sample loop.
    var threadManager: ThreadManager?
    var localAgentControl: LocalAgentControl?
    var skillsLookup: SessionSkillsLookup
    var turnInputContributors: [any TurnInputContributor]

    init(
        mcpRuntime: SessionMcpRuntime = SessionMcpRuntime(),
        execPolicy: Policy? = nil,
        showRawAgentReasoning: Bool = false,
        selectedCapabilityRoots: [String] = [],
        modelClient: SageCore.ModelClient? = nil,
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
        mcpToolTransport: (@Sendable (McpToolCallRequest) async throws -> CallToolResult)? = nil,
        ensureMcpConnected: (@Sendable () async -> Void)? = nil,
        reconnectMcp: (@Sendable () async -> Void)? = nil,
        disconnectMcp: (@Sendable ([String]) async -> Void)? = nil,
        persistRolloutItems: (@Sendable ([RolloutItem]) async throws -> Void)? = nil,
        sageToolSpecs: [SageToolSpec] = [],
        onSageToolCall: (@Sendable (String, String, String) async -> String?)? = nil,
        parallelAdmission: ParallelAdmission = ParallelAdmission(),
        turnDiffTracker: TurnDiffTracker = TurnDiffTracker(),
        approvalStore: ApprovalStore? = nil,
        hookProjectRoot: URL? = nil,
        hookActivatedSkills: [SkillRecord] = [],
        afterAgentHooks: [Hook] = [],
        threadManager: ThreadManager? = nil,
        localAgentControl: LocalAgentControl? = nil,
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
        self.mcpToolTransport = mcpToolTransport
        self.ensureMcpConnected = ensureMcpConnected
        self.reconnectMcp = reconnectMcp
        self.disconnectMcp = disconnectMcp
        self.persistRolloutItems = persistRolloutItems
        self.sageToolSpecs = sageToolSpecs
        self.onSageToolCall = onSageToolCall
        self.parallelAdmission = parallelAdmission
        self.turnDiffTracker = turnDiffTracker
        self.approvalStore = approvalStore
        self.hookProjectRoot = hookProjectRoot
        self.hookActivatedSkills = hookActivatedSkills
        self.afterAgentHooks = afterAgentHooks
        self.threadManager = threadManager
        self.localAgentControl = localAgentControl
        self.skillsLookup = skillsLookup
        self.turnInputContributors = turnInputContributors
    }
}

protocol TurnInputContributor: AnyObject {
    func contribute(userInput: [UserInput], turnId: String) async -> [ResponseItem]
}
