//
//  pre_tool_use.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/pre_tool_use.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview are faithful. `run` waits on the
//  command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct PreToolUseRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var subagent: SubagentHookContext?
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var matcherAliases: [String]
    public var toolUseId: String
    public var toolInput: JSONValue

    public init(
        sessionId: ThreadId,
        turnId: String,
        subagent: SubagentHookContext? = nil,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        toolName: String,
        matcherAliases: [String] = [],
        toolUseId: String,
        toolInput: JSONValue
    ) {
        self.sessionId = sessionId
        self.turnId = turnId
        self.subagent = subagent
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.toolName = toolName
        self.matcherAliases = matcherAliases
        self.toolUseId = toolUseId
        self.toolInput = toolInput
    }
}

public struct PreToolUseOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldBlock: Bool
    public var blockReason: String?
    public var additionalContexts: [String]
    public var updatedInput: JSONValue?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldBlock: Bool = false,
        blockReason: String? = nil,
        additionalContexts: [String] = [],
        updatedInput: JSONValue? = nil
    ) {
        self.hookEvents = hookEvents
        self.shouldBlock = shouldBlock
        self.blockReason = blockReason
        self.additionalContexts = additionalContexts
        self.updatedInput = updatedInput
    }
}

public func previewPreToolUse(
    handlers: [ConfiguredHandler],
    request: PreToolUseRequest
) -> [HookRunSummary] {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    return selectHandlersForMatcherInputs(
        handlers,
        eventName: .preToolUse,
        matcherInputs: inputs
    )
    .map { hookRunForToolUse(runningSummary($0), toolUseId: request.toolUseId) }
}

public func runPreToolUse(
    _ engine: ClaudeHooksEngine,
    request: PreToolUseRequest
) async throws -> PreToolUseOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("pre_tool_use hook run waits on CommandHookRuntime")
}
