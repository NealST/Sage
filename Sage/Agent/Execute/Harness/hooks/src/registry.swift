//
//  registry.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/registry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  HooksConfig / HookListOutcome / after-agent dispatch are faithful.
//  `Hooks.new` and `list_hooks` wait on ConfigLayerStack / discovery.
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
    public var shellProgram: String?
    public var shellArgs: [String]

    public init(
        legacyNotifyArgv: [String]? = nil,
        featureEnabled: Bool = false,
        bypassHookTrust: Bool = false,
        pluginHookSources: [PluginHookSource] = [],
        pluginHookLoadWarnings: [String] = [],
        shellProgram: String? = nil,
        shellArgs: [String] = []
    ) {
        self.legacyNotifyArgv = legacyNotifyArgv
        self.featureEnabled = featureEnabled
        self.bypassHookTrust = bypassHookTrust
        self.pluginHookSources = pluginHookSources
        self.pluginHookLoadWarnings = pluginHookLoadWarnings
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
    public var afterAgent: [Hook]
    public var engine: ClaudeHooksEngine
    public var pluginHookSources: [PluginHookSource]
    public var pluginHookLoadWarnings: [String]

    public init(
        afterAgent: [Hook] = [],
        engine: ClaudeHooksEngine,
        pluginHookSources: [PluginHookSource] = [],
        pluginHookLoadWarnings: [String] = []
    ) {
        self.afterAgent = afterAgent
        self.engine = engine
        self.pluginHookSources = pluginHookSources
        self.pluginHookLoadWarnings = pluginHookLoadWarnings
    }

    public static func `new`(
        config: HooksConfig,
        threadId: ThreadId,
        mcpExecutor: any HookMcpExecutor
    ) throws -> Hooks {
        _ = (config, threadId, mcpExecutor)
        throw CodexErr.unsupportedOperation(
            "Hooks::new waits on ConfigLayerStack / CommandHookRuntime"
        )
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

    public func shutdown() async {}

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

    func hooksForEvent(_ hookEvent: HookPayloadEvent) -> [Hook] {
        switch hookEvent {
        case .afterAgent:
            return afterAgent
        }
    }
}

public func listHooks() throws -> HookListOutcome {
    throw CodexErr.unsupportedOperation("list_hooks waits on ConfigLayerStack / discovery")
}
