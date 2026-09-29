//
//  engine_mod.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename collides with events/mod.swift.
//  Handler types, list entries, and run-id labels are faithful.
//  `ClaudeHooksEngine` construction waits on ConfigLayerStack / discovery.
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
    public var mcpExecutor: any HookMcpExecutor

    public init(
        handlers: [ConfiguredHandler] = [],
        warnings: [String] = [],
        requiredLoadErrors: [String] = [],
        mcpExecutor: any HookMcpExecutor
    ) {
        self.handlers = handlers
        self.warnings = warnings
        self.requiredLoadErrors = requiredLoadErrors
        self.mcpExecutor = mcpExecutor
    }

    public static func `new`() throws -> ClaudeHooksEngine {
        throw CodexErr.unsupportedOperation(
            "ClaudeHooksEngine::new waits on ConfigLayerStack / hook discovery"
        )
    }
}
