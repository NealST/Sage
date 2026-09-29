//
//  session_end.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/session_end.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, timeouts, and preview are faithful. `run` waits
//  on the command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

let SESSION_END_DEFAULT_TIMEOUT_SEC: UInt64 = 1
let SESSION_END_MAX_TIMEOUT_SEC: UInt64 = 3
let SESSION_END_REASON = "other"

public struct SessionEndRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?

    public init(
        sessionId: ThreadId,
        turnId: String,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil
    ) {
        self.sessionId = sessionId
        self.turnId = turnId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
    }
}

public struct SessionEndOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]

    public init(hookEvents: [HookCompletedEvent] = []) {
        self.hookEvents = hookEvents
    }
}

public func previewSessionEnd(handlers: [ConfiguredHandler]) -> [HookRunSummary] {
    selectHandlers(handlers, eventName: .sessionEnd, matcherInput: SESSION_END_REASON)
        .map(runningSummary)
}

public func runSessionEnd(
    _ engine: ClaudeHooksEngine,
    request: SessionEndRequest
) async throws -> SessionEndOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("session_end hook run waits on CommandHookRuntime")
}
