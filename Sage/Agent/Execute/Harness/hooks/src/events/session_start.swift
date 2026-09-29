//
//  session_start.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/session_start.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview are faithful. `run` waits on the
//  command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

public enum SessionStartSource: Equatable, Sendable {
    case startup
    case resume
    case clear
    case compact
    case fork

    public func asStr() -> String {
        switch self {
        case .startup: return "startup"
        case .resume: return "resume"
        case .clear: return "clear"
        case .compact: return "compact"
        case .fork: return "fork"
        }
    }
}

public struct SessionStartRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var target: StartHookTarget

    public init(
        sessionId: ThreadId,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        target: StartHookTarget
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.target = target
    }
}

public enum StartHookTarget: Equatable, Sendable {
    case sessionStart(source: SessionStartSource)
    case subagentStart(turnId: String, agentId: String, agentType: String)

    public func eventName() -> HookEventName {
        switch self {
        case .sessionStart: return .sessionStart
        case .subagentStart: return .subagentStart
        }
    }

    public func matcherInput() -> String {
        switch self {
        case .sessionStart(let source): return source.asStr()
        case .subagentStart(_, _, let agentType): return agentType
        }
    }
}

public struct SessionStartOutcome: Equatable, Sendable {
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

public func previewSessionStart(
    handlers: [ConfiguredHandler],
    request: SessionStartRequest
) -> [HookRunSummary] {
    selectHandlers(
        handlers,
        eventName: request.target.eventName(),
        matcherInput: request.target.matcherInput()
    )
    .map(runningSummary)
}

public func runSessionStart(
    _ engine: ClaudeHooksEngine,
    request: SessionStartRequest
) async throws -> SessionStartOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("session_start hook run waits on CommandHookRuntime")
}
