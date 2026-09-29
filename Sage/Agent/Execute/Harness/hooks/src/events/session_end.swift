//
//  session_end.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/session_end.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, timeouts, preview, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
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
) async -> SessionEndOutcome {
    let matched = selectHandlers(engine.handlers, eventName: .sessionEnd, matcherInput: SESSION_END_REASON)
    if matched.isEmpty {
        return SessionEndOutcome()
    }

    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: commandInputJSON(request),
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        parse: parseSessionEndCompleted
    )
    return SessionEndOutcome(hookEvents: results.map(\.completed))
}

func commandInputJSON(_ request: SessionEndRequest) -> String {
    SessionEndCommandInput(
        sessionId: request.sessionId.description,
        transcriptPath: .fromPath(request.transcriptPath),
        cwd: request.cwd.asPath,
        hookEventName: "SessionEnd",
        reason: SESSION_END_REASON
    ).encodedJSON()
}

func parseSessionEndCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<Void> {
    let status: HookRunStatus
    let entries: [HookOutputEntry]
    if let error = runResult.error {
        status = .failed
        entries = [HookOutputEntry(kind: .error, text: error)]
    } else if let exitCode = runResult.exitCode {
        if exitCode == 0 {
            status = .completed
            entries = []
        } else {
            status = .failed
            entries = [
                HookOutputEntry(
                    kind: .error,
                    text: trimmedNonEmpty(runResult.stderr) ?? "hook exited with code \(exitCode)"
                ),
            ]
        }
    } else {
        status = .failed
        entries = [HookOutputEntry(kind: .error, text: "hook process terminated without an exit code")]
    }

    return ParsedHandler(
        completed: HookCompletedEvent(
            turnId: turnId,
            run: completedSummary(handler, runResult: runResult, status: status, entries: entries)
        ),
        data: (),
        completionOrder: 0
    )
}
