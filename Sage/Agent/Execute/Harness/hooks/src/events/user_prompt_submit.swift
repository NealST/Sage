//
//  user_prompt_submit.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/user_prompt_submit.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview are faithful. `run` waits on the
//  command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct UserPromptSubmitRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var subagent: SubagentHookContext?
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var prompt: String

    public init(
        sessionId: ThreadId,
        turnId: String,
        subagent: SubagentHookContext? = nil,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        prompt: String
    ) {
        self.sessionId = sessionId
        self.turnId = turnId
        self.subagent = subagent
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.prompt = prompt
    }
}

public struct UserPromptSubmitOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?
    public var additionalContexts: [String]

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldStop: Bool = false,
        stopReason: String? = nil,
        additionalContexts: [String] = []
    ) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.additionalContexts = additionalContexts
    }
}

public func previewUserPromptSubmit(
    handlers: [ConfiguredHandler],
    request: UserPromptSubmitRequest
) -> [HookRunSummary] {
    _ = request
    return selectHandlers(handlers, eventName: .userPromptSubmit, matcherInput: nil)
        .map(runningSummary)
}

public func runUserPromptSubmit(
    _ engine: ClaudeHooksEngine,
    request: UserPromptSubmitRequest
) async throws -> UserPromptSubmitOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("user_prompt_submit hook run waits on CommandHookRuntime")
}
