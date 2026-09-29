//
//  registry.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/registry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Hooks.new / from_config / list_hooks / preview+run wrappers are ported.
//  hooks.json folders are discovered without walking a ConfigLayerStack.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct HooksConfig: Sendable {
    public var legacyNotifyArgv: [String]?
    public var featureEnabled: Bool
    public var bypassHookTrust: Bool
    public var pluginHookSources: [PluginHookSource]
    public var pluginHookLoadWarnings: [String]
    public var hooksJsonFolders: [AbsolutePathBuf]
    public var hookStates: [String: HookStateToml]
    public var shellProgram: String?
    public var shellArgs: [String]

    public init(
        legacyNotifyArgv: [String]? = nil,
        featureEnabled: Bool = false,
        bypassHookTrust: Bool = false,
        pluginHookSources: [PluginHookSource] = [],
        pluginHookLoadWarnings: [String] = [],
        hooksJsonFolders: [AbsolutePathBuf] = [],
        hookStates: [String: HookStateToml] = [:],
        shellProgram: String? = nil,
        shellArgs: [String] = []
    ) {
        self.legacyNotifyArgv = legacyNotifyArgv
        self.featureEnabled = featureEnabled
        self.bypassHookTrust = bypassHookTrust
        self.pluginHookSources = pluginHookSources
        self.pluginHookLoadWarnings = pluginHookLoadWarnings
        self.hooksJsonFolders = hooksJsonFolders
        self.hookStates = hookStates
        self.shellProgram = shellProgram
        self.shellArgs = shellArgs
    }
}

public struct HookListOutcome: Equatable, Sendable {
    public var hooks: [HookListEntry]
    public var warnings: [String]

    public init(hooks: [HookListEntry] = [], warnings: [String] = []) {
        self.hooks = hooks
        self.warnings = warnings
    }
}

public final class Hooks: @unchecked Sendable {
    var environment: [(String, String)]
    public var afterAgent: [Hook]
    public var engine: ClaudeHooksEngine
    public var pluginHookSources: [PluginHookSource]
    public var pluginHookLoadWarnings: [String]

    public init(
        environment: [(String, String)] = [],
        afterAgent: [Hook] = [],
        engine: ClaudeHooksEngine,
        pluginHookSources: [PluginHookSource] = [],
        pluginHookLoadWarnings: [String] = []
    ) {
        self.environment = environment
        self.afterAgent = afterAgent
        self.engine = engine
        self.pluginHookSources = pluginHookSources
        self.pluginHookLoadWarnings = pluginHookLoadWarnings
    }

    public static func `new`(
        config: HooksConfig,
        threadId: ThreadId,
        mcpExecutor: any HookMcpExecutor
    ) throws -> (Hooks, HookCompletedMailbox) {
        let mailbox = HookCompletedMailbox()
        let environment = ProcessInfo.processInfo.environment.map { ($0.key, $0.value) }
        let hooks = fromConfig(
            config: config,
            mcpExecutor: mcpExecutor,
            environment: environment
        ) { shell in
            CommandHookRuntime(
                shell: shell,
                environment: environment,
                threadId: threadId,
                resultSender: mailbox
            )
        }
        let requiredLoadErrors = hooks.engine.requiredLoadErrors
        if !requiredLoadErrors.isEmpty {
            throw CodexErr.invalidRequest(
                "failed to load required managed hooks: \(requiredLoadErrors.joined(separator: "; "))"
            )
        }
        return (hooks, mailbox)
    }

    public func reconfigured(_ config: HooksConfig) -> Hooks {
        Self.fromConfig(
            config: config,
            mcpExecutor: engine.mcpExecutor,
            environment: environment
        ) { shell in
            engine.commandRuntime.reconfigured(shell)
        }
    }

    public func matchesPluginHooks(
        sources: [PluginHookSource],
        warnings: [String]
    ) -> Bool {
        pluginHookSources == sources && pluginHookLoadWarnings == warnings
    }

    public func startupWarnings() -> [String] {
        engine.warnings
    }

    public func shutdown() async {
        await engine.commandRuntime.shutdown()
    }

    public func dispatch(_ hookPayload: HookPayload) async -> [HookResponse] {
        let hooks = hooksForEvent(hookPayload.hookEvent)
        var outcomes: [HookResponse] = []
        outcomes.reserveCapacity(hooks.count)
        for hook in hooks {
            let outcome = await hook.execute(hookPayload)
            let shouldAbort = outcome.result.shouldAbortOperation
            outcomes.append(outcome)
            if shouldAbort { break }
        }
        return outcomes
    }

    public func previewSessionStart(_ request: SessionStartRequest) -> [HookRunSummary] {
        engine.previewSessionStart(request)
    }

    public func previewPreToolUse(_ request: PreToolUseRequest) -> [HookRunSummary] {
        engine.previewPreToolUse(request)
    }

    public func previewPermissionRequest(_ request: PermissionRequestRequest) -> [HookRunSummary] {
        engine.previewPermissionRequest(request)
    }

    public func maxPermissionRequestTimeout() -> TimeInterval {
        engine.maxPermissionRequestTimeout()
    }

    public func previewPostToolUse(_ request: PostToolUseRequest) -> [HookRunSummary] {
        engine.previewPostToolUse(request)
    }

    public func runSessionStart(
        _ request: SessionStartRequest,
        turnId: String? = nil
    ) async -> SessionStartOutcome {
        await engine.runSessionStart(request, turnId: turnId)
    }

    public func runPreToolUse(_ request: PreToolUseRequest) async -> PreToolUseOutcome {
        await engine.runPreToolUse(request)
    }

    public func runPermissionRequest(_ request: PermissionRequestRequest) async -> PermissionRequestOutcome {
        await engine.runPermissionRequest(request)
    }

    public func runPostToolUse(_ request: PostToolUseRequest) async -> PostToolUseOutcome {
        await engine.runPostToolUse(request)
    }

    public func previewPreCompact(_ request: PreCompactRequest) -> [HookRunSummary] {
        engine.previewPreCompact(request)
    }

    public func runPreCompact(_ request: PreCompactRequest) async -> PreCompactOutcome {
        await engine.runPreCompact(request)
    }

    public func previewPostCompact(_ request: PostCompactRequest) -> [HookRunSummary] {
        engine.previewPostCompact(request)
    }

    public func runPostCompact(_ request: PostCompactRequest) async -> StatelessHookOutcome {
        await engine.runPostCompact(request)
    }

    public func previewUserPromptSubmit(_ request: UserPromptSubmitRequest) -> [HookRunSummary] {
        engine.previewUserPromptSubmit(request)
    }

    public func runUserPromptSubmit(_ request: UserPromptSubmitRequest) async -> UserPromptSubmitOutcome {
        await engine.runUserPromptSubmit(request)
    }

    public func previewStop(_ request: StopRequest) -> [HookRunSummary] {
        engine.previewStop(request)
    }

    public func runStop(_ request: StopRequest) async -> StopOutcome {
        await engine.runStop(request)
    }

    public func previewSessionEnd() -> [HookRunSummary] {
        engine.previewSessionEnd()
    }

    public func runSessionEnd(_ request: SessionEndRequest) async -> SessionEndOutcome {
        await engine.runSessionEnd(request)
    }

    public func previewInterrupt() -> [HookRunSummary] {
        engine.previewInterrupt()
    }

    public func runInterrupt(_ request: InterruptRequest) async -> InterruptOutcome {
        await engine.runInterrupt(request)
    }

    func hooksForEvent(_ hookEvent: HookPayloadEvent) -> [Hook] {
        switch hookEvent {
        case .afterAgent:
            return afterAgent
        }
    }

    static func fromConfig(
        config: HooksConfig,
        mcpExecutor: any HookMcpExecutor,
        environment: [(String, String)],
        buildRuntime: (CommandShell) -> CommandHookRuntime
    ) -> Hooks {
        let afterAgent: [Hook]
        if let argv = config.legacyNotifyArgv, !argv.isEmpty, !(argv.first?.isEmpty ?? true) {
            afterAgent = [notifyHook(argv: argv, environment: environment)]
        } else {
            afterAgent = []
        }
        let commandRuntime = buildRuntime(
            CommandShell(program: config.shellProgram ?? "", args: config.shellArgs)
        )
        let engine = ClaudeHooksEngine.new(
            enabled: config.featureEnabled,
            bypassHookTrust: config.bypassHookTrust,
            pluginHookSources: config.pluginHookSources,
            pluginHookLoadWarnings: config.pluginHookLoadWarnings,
            hooksJsonFolders: config.hooksJsonFolders,
            hookStates: config.hookStates,
            commandRuntime: commandRuntime,
            mcpExecutor: mcpExecutor
        )
        return Hooks(
            environment: environment,
            afterAgent: afterAgent,
            engine: engine,
            pluginHookSources: config.pluginHookSources,
            pluginHookLoadWarnings: config.pluginHookLoadWarnings
        )
    }
}

public func listHooks(_ config: HooksConfig) -> HookListOutcome {
    if !config.featureEnabled {
        return HookListOutcome()
    }
    let discovered = discoverHandlers(
        hooksJsonFolders: config.hooksJsonFolders,
        hookStates: config.hookStates,
        pluginHookSources: config.pluginHookSources,
        pluginHookLoadWarnings: config.pluginHookLoadWarnings,
        bypassHookTrust: config.bypassHookTrust
    )
    return HookListOutcome(hooks: discovered.hookEntries, warnings: discovered.warnings)
}

func commandFromArgv(
    _ argv: [String],
    environment: [(String, String)]
) -> HookProcessSpec? {
    guard let program = argv.first, !program.isEmpty else { return nil }
    var env: [String: String] = [:]
    for (key, value) in environment {
        env[key] = value
    }
    scrubNonInheritableEnvVars(&env)
    return HookProcessSpec(program: program, arguments: Array(argv.dropFirst()), environment: env)
}
