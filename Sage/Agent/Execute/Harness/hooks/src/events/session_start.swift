//
//  session_start.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/session_start.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview, stdin JSON, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
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
    request: SessionStartRequest,
    turnId: String? = nil
) async -> SessionStartOutcome {
    let matched = selectHandlers(
        engine.handlers,
        eventName: request.target.eventName(),
        matcherInput: request.target.matcherInput()
    )
    if matched.isEmpty {
        return SessionStartOutcome()
    }

    let (inputJSON, resolvedTurnId) = commandInputJSON(request, turnId: turnId)
    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: inputJSON,
        cwd: request.cwd.asPath,
        turnId: resolvedTurnId,
        parse: parseSessionStartCompleted
    )
    let additionalContexts = await engine.commandRuntime.outputSpiller.maybeSpillAdditionalContexts(
        flattenAdditionalContexts(results.map(\.data.additionalContextsForModel))
    )
    return SessionStartOutcome(
        hookEvents: results.map(\.completed),
        shouldStop: results.contains { $0.data.shouldStop },
        stopReason: results.compactMap(\.data.stopReason).first,
        additionalContexts: additionalContexts
    )
}

func commandInputJSON(
    _ request: SessionStartRequest,
    turnId: String?
) -> (String, String?) {
    switch request.target {
    case .sessionStart(let source):
        let inputJSON = SessionStartCommandInput(
            sessionId: request.sessionId.description,
            transcriptPath: request.transcriptPath,
            cwd: request.cwd.asPath,
            model: request.model,
            permissionMode: request.permissionMode,
            source: source.asStr()
        ).encodedJSON()
        return (inputJSON, turnId)
    case .subagentStart(let subagentTurnId, let agentId, let agentType):
        let inputJSON = SubagentStartCommandInput(
            sessionId: request.sessionId.description,
            turnId: subagentTurnId,
            transcriptPath: .fromPath(request.transcriptPath),
            cwd: request.cwd.asPath,
            hookEventName: "SubagentStart",
            model: request.model,
            permissionMode: request.permissionMode,
            agentId: agentId,
            agentType: agentType
        ).encodedJSON()
        return (inputJSON, subagentTurnId)
    }
}

struct SessionStartHandlerData: Equatable, Sendable {
    var shouldStop: Bool
    var stopReason: String?
    var additionalContextsForModel: [AdditionalContext]
}

func parseSessionStartCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<SessionStartHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed
    var shouldStop = false
    var stopReason: String?
    var additionalContextsForModel: [AdditionalContext] = []

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
            } else if let parsed = parseStartOutput(handler.eventName, stdout: runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                if let additionalContext = parsed.additionalContext {
                    appendAdditionalContext(
                        entries: &entries,
                        additionalContextsForModel: &additionalContextsForModel,
                        handler: handler,
                        additionalContext: additionalContext
                    )
                }
                _ = parsed.universal.suppressOutput
                if handler.canApplyControlEffects(),
                   handler.eventName == .sessionStart,
                   !parsed.universal.continueProcessing
                {
                    status = .stopped
                    shouldStop = true
                    stopReason = parsed.universal.stopReason
                    if let stopReasonText = parsed.universal.stopReason {
                        entries.append(HookOutputEntry(kind: .stop, text: stopReasonText))
                    }
                }
            } else if looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: invalidStartJSONMessage(handler.eventName)
                ))
            } else {
                appendAdditionalContext(
                    entries: &entries,
                    additionalContextsForModel: &additionalContextsForModel,
                    handler: handler,
                    additionalContext: trimmedStdout
                )
            }
        case let exitCode?:
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: "hook exited with code \(exitCode)"))
        case nil:
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: "hook exited without a status code"))
        }
    }

    return ParsedHandler(
        completed: HookCompletedEvent(
            turnId: turnId,
            run: completedSummary(handler, runResult: runResult, status: status, entries: entries)
        ),
        data: SessionStartHandlerData(
            shouldStop: shouldStop,
            stopReason: stopReason,
            additionalContextsForModel: additionalContextsForModel
        ),
        completionOrder: 0
    )
}

private func parseStartOutput(_ eventName: HookEventName, stdout: String) -> SessionStartOutput? {
    switch eventName {
    case .sessionStart:
        return parseSessionStart(stdout)
    case .subagentStart:
        return parseSubagentStart(stdout)
    default:
        preconditionFailure("expected start hook event, got \(eventName)")
    }
}

private func invalidStartJSONMessage(_ eventName: HookEventName) -> String {
    switch eventName {
    case .sessionStart:
        return "hook returned invalid session start JSON output"
    case .subagentStart:
        return "hook returned invalid subagent start JSON output"
    default:
        preconditionFailure("expected start hook event, got \(eventName)")
    }
}
