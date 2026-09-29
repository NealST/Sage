//
//  post_tool_use.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/post_tool_use.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview are faithful. `run` waits on the
//  command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct PostToolUseRequest: Equatable, Sendable {
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
    public var toolResponse: JSONValue

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
        toolInput: JSONValue,
        toolResponse: JSONValue
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
        self.toolResponse = toolResponse
    }
}

public struct PostToolUseOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldBlock: Bool
    public var additionalContexts: [String]
    public var feedbackMessage: String?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldBlock: Bool = false,
        additionalContexts: [String] = [],
        feedbackMessage: String? = nil
    ) {
        self.hookEvents = hookEvents
        self.shouldBlock = shouldBlock
        self.additionalContexts = additionalContexts
        self.feedbackMessage = feedbackMessage
    }
}

public func previewPostToolUse(
    handlers: [ConfiguredHandler],
    request: PostToolUseRequest
) -> [HookRunSummary] {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    return selectHandlersForMatcherInputs(
        handlers,
        eventName: .postToolUse,
        matcherInputs: inputs
    )
    .map { hookRunForToolUse(runningSummary($0), toolUseId: request.toolUseId) }
}

public func runPostToolUse(
    _ engine: ClaudeHooksEngine,
    request: PostToolUseRequest
) async throws -> PostToolUseOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("post_tool_use hook run waits on CommandHookRuntime")
}
