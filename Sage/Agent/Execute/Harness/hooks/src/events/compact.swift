//
//  compact.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/compact.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview are faithful. `run` waits on the
//  command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct PreCompactRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var subagent: SubagentHookContext?
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var trigger: String

    public init(
        sessionId: ThreadId,
        turnId: String,
        subagent: SubagentHookContext? = nil,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        trigger: String
    ) {
        self.sessionId = sessionId
        self.turnId = turnId
        self.subagent = subagent
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.trigger = trigger
    }
}

public struct PostCompactRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var subagent: SubagentHookContext?
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var trigger: String

    public init(
        sessionId: ThreadId,
        turnId: String,
        subagent: SubagentHookContext? = nil,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        trigger: String
    ) {
        self.sessionId = sessionId
        self.turnId = turnId
        self.subagent = subagent
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.trigger = trigger
    }
}

public struct StatelessHookOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldStop: Bool = false,
        stopReason: String? = nil
    ) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
    }
}

public struct PreCompactOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldStop: Bool = false,
        stopReason: String? = nil
    ) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
    }
}

public func previewPreCompact(
    handlers: [ConfiguredHandler],
    request: PreCompactRequest
) -> [HookRunSummary] {
    selectHandlers(handlers, eventName: .preCompact, matcherInput: request.trigger)
        .map(runningSummary)
}

public func previewPostCompact(
    handlers: [ConfiguredHandler],
    request: PostCompactRequest
) -> [HookRunSummary] {
    selectHandlers(handlers, eventName: .postCompact, matcherInput: request.trigger)
        .map(runningSummary)
}

public func runPreCompact(
    _ engine: ClaudeHooksEngine,
    request: PreCompactRequest
) async throws -> PreCompactOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("pre_compact hook run waits on CommandHookRuntime")
}

public func runPostCompact(
    _ engine: ClaudeHooksEngine,
    request: PostCompactRequest
) async throws -> StatelessHookOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("post_compact hook run waits on CommandHookRuntime")
}
