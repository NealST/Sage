//
//  engine_mod.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename collides with events/mod.swift.
//  Handler types, list entries, run-id labels, and preview/run wrappers
//  are ported. `new` discovers hooks.json folders and plugin-source
//  warnings without walking a ConfigLayerStack.
//  `PluginId` is a string until the plugin crate is ported.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct CommandShell: Equatable, Sendable {
    public var program: String
    public var args: [String]

    public init(program: String, args: [String] = []) {
        self.program = program
        self.args = args
    }
}

public struct ConfiguredHandler: Equatable, Sendable {
    public var builtin: Bool
    public var eventName: HookEventName
    public var matcher: String?
    public var timeoutSec: UInt64
    public var statusMessage: String?
    public var additionalContextLimit: AdditionalContextLimit
    public var sourcePath: HandlerSourcePath
    public var source: HookSource
    public var displayOrder: Int64
    public var kind: ConfiguredHandlerKind

    public init(
        builtin: Bool = false,
        eventName: HookEventName,
        matcher: String? = nil,
        timeoutSec: UInt64,
        statusMessage: String? = nil,
        additionalContextLimit: AdditionalContextLimit = .default,
        sourcePath: HandlerSourcePath,
        source: HookSource = .unknown,
        displayOrder: Int64,
        kind: ConfiguredHandlerKind
    ) {
        self.builtin = builtin
        self.eventName = eventName
        self.matcher = matcher
        self.timeoutSec = timeoutSec
        self.statusMessage = statusMessage
        self.additionalContextLimit = additionalContextLimit
        self.sourcePath = sourcePath
        self.source = source
        self.displayOrder = displayOrder
        self.kind = kind
    }

    public func executionMode() -> HookExecutionMode {
        if case .executorScoped = sourcePath { return .async }
        switch kind {
        case .command(_, _, let isAsync):
            return isAsync ? .async : .sync
        case .mcpTool:
            return .sync
        }
    }

    public func canApplyControlEffects() -> Bool {
        executionMode() == .sync
    }

    public func runId() -> String {
        "\(eventNameLabel()):\(displayOrder):\(sourcePath)"
    }

    public func handlerType() -> HookHandlerType {
        switch kind {
        case .command: return .command
        case .mcpTool: return .mcpTool
        }
    }

    func eventNameLabel() -> String {
        switch eventName {
        case .preToolUse: return "pre-tool-use"
        case .permissionRequest: return "permission-request"
        case .postToolUse: return "post-tool-use"
        case .preCompact: return "pre-compact"
        case .postCompact: return "post-compact"
        case .sessionStart: return "session-start"
        case .sessionEnd: return "session-end"
        case .userPromptSubmit: return "user-prompt-submit"
        case .subagentStart: return "subagent-start"
        case .subagentStop: return "subagent-stop"
        case .stop: return "stop"
        case .interrupt: return "interrupt"
        }
    }
}

public enum HandlerSourcePath: Equatable, Sendable, CustomStringConvertible {
    case local(AbsolutePathBuf)
    case executorScoped(
        pluginId: String,
        environmentId: String,
        mcpEnvironmentId: String?,
        mcpMetadata: [String: JSONValue]?,
        manifestPath: PathUri,
        sourceRelativePath: String
    )

    public var description: String {
        switch self {
        case .local(let path):
            return path.display
        case .executorScoped(_, let environmentId, _, _, let manifestPath, let sourceRelativePath):
            return "\(environmentId):\(manifestPath):\(sourceRelativePath)"
        }
    }
}

public enum ConfiguredHandlerKind: Equatable, Sendable {
    case command(command: String, env: [String: String], isAsync: Bool)
    case mcpTool(server: String, tool: String, input: [String: JSONValue])
}

public struct HandlerRunResult: Equatable, Sendable {
    public var startedAt: Int64
    public var completedAt: Int64
    public var durationMs: Int64
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var error: String?

    public init(
        startedAt: Int64,
        completedAt: Int64,
        durationMs: Int64,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        error: String? = nil
    ) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.error = error
    }
}

public enum HookListEntryHandler: Equatable, Sendable {
    case command(command: String, isAsync: Bool)
    case mcpTool(server: String, tool: String)
}

public struct HookListEntry: Equatable, Sendable {
    public var builtin: Bool
    public var key: String
    public var eventName: HookEventName
    public var handler: HookListEntryHandler
    public var matcher: String?
    public var timeoutSec: UInt64
    public var statusMessage: String?
    public var additionalContextLimit: Int?
    public var sourcePath: AbsolutePathBuf
    public var source: HookSource
    public var pluginId: String?
    public var displayOrder: Int64
    public var enabled: Bool
    public var isManaged: Bool
    public var currentHash: String
    public var trustStatus: HookTrustStatus

    public init(
        builtin: Bool = false,
        key: String,
        eventName: HookEventName,
        handler: HookListEntryHandler,
        matcher: String? = nil,
        timeoutSec: UInt64,
        statusMessage: String? = nil,
        additionalContextLimit: Int? = nil,
        sourcePath: AbsolutePathBuf,
        source: HookSource,
        pluginId: String? = nil,
        displayOrder: Int64,
        enabled: Bool,
        isManaged: Bool,
        currentHash: String,
        trustStatus: HookTrustStatus
    ) {
        self.builtin = builtin
        self.key = key
        self.eventName = eventName
        self.handler = handler
        self.matcher = matcher
        self.timeoutSec = timeoutSec
        self.statusMessage = statusMessage
        self.additionalContextLimit = additionalContextLimit
        self.sourcePath = sourcePath
        self.source = source
        self.pluginId = pluginId
        self.displayOrder = displayOrder
        self.enabled = enabled
        self.isManaged = isManaged
        self.currentHash = currentHash
        self.trustStatus = trustStatus
    }
}

public final class ClaudeHooksEngine: @unchecked Sendable {
    public var handlers: [ConfiguredHandler]
    public var warnings: [String]
    public var requiredLoadErrors: [String]
    public var commandRuntime: CommandHookRuntime
    public var mcpExecutor: any HookMcpExecutor

    public init(
        handlers: [ConfiguredHandler] = [],
        warnings: [String] = [],
        requiredLoadErrors: [String] = [],
        commandRuntime: CommandHookRuntime,
        mcpExecutor: any HookMcpExecutor
    ) {
        self.handlers = handlers
        self.warnings = warnings
        self.requiredLoadErrors = requiredLoadErrors
        self.commandRuntime = commandRuntime
        self.mcpExecutor = mcpExecutor
    }

    public static func `new`(
        enabled: Bool,
        bypassHookTrust: Bool = false,
        pluginHookSources: [PluginHookSource] = [],
        pluginHookLoadWarnings: [String] = [],
        hooksJsonFolders: [AbsolutePathBuf] = [],
        hookStates: [String: HookStateToml] = [:],
        commandRuntime: CommandHookRuntime,
        mcpExecutor: any HookMcpExecutor
    ) -> ClaudeHooksEngine {
        if !enabled && pluginHookSources.isEmpty && hooksJsonFolders.isEmpty {
            return ClaudeHooksEngine(commandRuntime: commandRuntime, mcpExecutor: mcpExecutor)
        }
        _ = generatedHookSchemas()
        var discovered = discoverHandlers(
            hooksJsonFolders: hooksJsonFolders,
            hookStates: hookStates,
            pluginHookSources: pluginHookSources,
            pluginHookLoadWarnings: pluginHookLoadWarnings,
            bypassHookTrust: bypassHookTrust
        )
        if !enabled {
            discovered.handlers.removeAll { !$0.builtin }
            discovered.warnings = []
            discovered.requiredLoadErrors = []
        }
        return ClaudeHooksEngine(
            handlers: discovered.handlers,
            warnings: discovered.warnings,
            requiredLoadErrors: discovered.requiredLoadErrors,
            commandRuntime: commandRuntime,
            mcpExecutor: mcpExecutor
        )
    }

    public func maxPermissionRequestTimeout() -> TimeInterval {
        TimeInterval(
            handlers
                .filter { $0.eventName == .permissionRequest && $0.canApplyControlEffects() }
                .map(\.timeoutSec)
                .max() ?? 0
        )
    }

    public func previewSessionStart(_ request: SessionStartRequest) -> [HookRunSummary] {
        CodexHooks.previewSessionStart(handlers: handlers, request: request)
    }

    public func previewPreToolUse(_ request: PreToolUseRequest) -> [HookRunSummary] {
        CodexHooks.previewPreToolUse(handlers: handlers, request: request)
    }

    public func previewPermissionRequest(_ request: PermissionRequestRequest) -> [HookRunSummary] {
        CodexHooks.previewPermissionRequest(handlers: handlers, request: request)
    }

    public func previewPostToolUse(_ request: PostToolUseRequest) -> [HookRunSummary] {
        CodexHooks.previewPostToolUse(handlers: handlers, request: request)
    }

    public func previewPreCompact(_ request: PreCompactRequest) -> [HookRunSummary] {
        CodexHooks.previewPreCompact(handlers: handlers, request: request)
    }

    public func previewPostCompact(_ request: PostCompactRequest) -> [HookRunSummary] {
        CodexHooks.previewPostCompact(handlers: handlers, request: request)
    }

    public func previewUserPromptSubmit(_ request: UserPromptSubmitRequest) -> [HookRunSummary] {
        CodexHooks.previewUserPromptSubmit(handlers: handlers, request: request)
    }

    public func previewStop(_ request: StopRequest) -> [HookRunSummary] {
        CodexHooks.previewStop(handlers: handlers, request: request)
    }

    public func previewSessionEnd() -> [HookRunSummary] {
        CodexHooks.previewSessionEnd(handlers: handlers)
    }

    public func previewInterrupt() -> [HookRunSummary] {
        CodexHooks.previewInterrupt(handlers: handlers)
    }

    public func runSessionStart(
        _ request: SessionStartRequest,
        turnId: String? = nil
    ) async -> SessionStartOutcome {
        await CodexHooks.runSessionStart(self, request: request, turnId: turnId)
    }

    public func runPreToolUse(_ request: PreToolUseRequest) async -> PreToolUseOutcome {
        await CodexHooks.runPreToolUse(self, request: request)
    }

    public func runPermissionRequest(_ request: PermissionRequestRequest) async -> PermissionRequestOutcome {
        await CodexHooks.runPermissionRequest(self, request: request)
    }

    public func runPostToolUse(_ request: PostToolUseRequest) async -> PostToolUseOutcome {
        var outcome = await CodexHooks.runPostToolUse(self, request: request)
        if let feedback = outcome.feedbackMessage {
            outcome.feedbackMessage = await commandRuntime.outputSpiller.maybeSpillText(feedback)
        }
        return outcome
    }

    public func runPreCompact(_ request: PreCompactRequest) async -> PreCompactOutcome {
        await CodexHooks.runPreCompact(self, request: request)
    }

    public func runPostCompact(_ request: PostCompactRequest) async -> StatelessHookOutcome {
        await CodexHooks.runPostCompact(self, request: request)
    }

    public func runUserPromptSubmit(_ request: UserPromptSubmitRequest) async -> UserPromptSubmitOutcome {
        await CodexHooks.runUserPromptSubmit(self, request: request)
    }

    public func runStop(_ request: StopRequest) async -> StopOutcome {
        var outcome = await CodexHooks.runStop(self, request: request)
        outcome.continuationFragments = await commandRuntime.outputSpiller.maybeSpillPromptFragments(
            outcome.continuationFragments
        )
        return outcome
    }

    public func runSessionEnd(_ request: SessionEndRequest) async -> SessionEndOutcome {
        await CodexHooks.runSessionEnd(self, request: request)
    }

    public func runInterrupt(_ request: InterruptRequest) async -> InterruptOutcome {
        await CodexHooks.runInterrupt(self, request: request)
    }
}
