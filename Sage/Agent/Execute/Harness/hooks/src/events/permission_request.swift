//
//  permission_request.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/permission_request.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview are faithful. `run` waits on the
//  command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct PermissionRequestRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var subagent: SubagentHookContext?
    public var cwd: String
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var matcherAliases: [String]
    public var runIdSuffix: String
    public var toolInput: JSONValue

    public init(
        sessionId: ThreadId,
        turnId: String,
        subagent: SubagentHookContext? = nil,
        cwd: String,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        toolName: String,
        matcherAliases: [String] = [],
        runIdSuffix: String,
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
        self.runIdSuffix = runIdSuffix
        self.toolInput = toolInput
    }
}

public enum PermissionRequestDecision: Equatable, Sendable {
    case allow
    case deny(message: String)
}

public struct PermissionRequestOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var decision: PermissionRequestDecision?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        decision: PermissionRequestDecision? = nil
    ) {
        self.hookEvents = hookEvents
        self.decision = decision
    }
}

public func previewPermissionRequest(
    handlers: [ConfiguredHandler],
    request: PermissionRequestRequest
) -> [HookRunSummary] {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    return selectHandlersForMatcherInputs(
        handlers,
        eventName: .permissionRequest,
        matcherInputs: inputs
    )
    .map { hookRunForToolUse(runningSummary($0), toolUseId: request.runIdSuffix) }
}

public func runPermissionRequest(
    _ engine: ClaudeHooksEngine,
    request: PermissionRequestRequest
) async throws -> PermissionRequestOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("permission_request hook run waits on CommandHookRuntime")
}
