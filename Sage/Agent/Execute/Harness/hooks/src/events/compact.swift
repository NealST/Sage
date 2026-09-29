//
//  compact.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/compact.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview, stdin JSON, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
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
) async -> PreCompactOutcome {
    let matched = selectHandlers(engine.handlers, eventName: .preCompact, matcherInput: request.trigger)
    if matched.isEmpty {
        return PreCompactOutcome()
    }

    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: commandInputJSON(request),
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        parse: parsePreCompactCompleted
    )
    return PreCompactOutcome(
        hookEvents: results.map(\.completed),
        shouldStop: results.contains { $0.data.shouldStop },
        stopReason: results.compactMap(\.data.stopReason).first
    )
}

public func runPostCompact(
    _ engine: ClaudeHooksEngine,
    request: PostCompactRequest
) async -> StatelessHookOutcome {
    let matched = selectHandlers(engine.handlers, eventName: .postCompact, matcherInput: request.trigger)
    if matched.isEmpty {
        return StatelessHookOutcome()
    }

    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: commandInputJSON(request),
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        parse: parsePostCompactCompleted
    )
    return StatelessHookOutcome(
        hookEvents: results.map(\.completed),
        shouldStop: results.contains { $0.data.shouldStop },
        stopReason: results.compactMap(\.data.stopReason).first
    )
}

func commandInputJSON(_ request: PreCompactRequest) -> String {
    let subagent = SubagentCommandInputFields(request.subagent)
    return PreCompactCommandInput(
        sessionId: request.sessionId.description,
        turnId: request.turnId,
        agentId: subagent.agentId,
        agentType: subagent.agentType,
        transcriptPath: .fromPath(request.transcriptPath),
        cwd: request.cwd.asPath,
        hookEventName: "PreCompact",
        model: request.model,
        trigger: request.trigger
    ).encodedJSON()
}

func commandInputJSON(_ request: PostCompactRequest) -> String {
    let subagent = SubagentCommandInputFields(request.subagent)
    return PostCompactCommandInput(
        sessionId: request.sessionId.description,
        turnId: request.turnId,
        agentId: subagent.agentId,
        agentType: subagent.agentType,
        transcriptPath: .fromPath(request.transcriptPath),
        cwd: request.cwd.asPath,
        hookEventName: "PostCompact",
        model: request.model,
        trigger: request.trigger
    ).encodedJSON()
}

struct CompactHandlerData: Equatable, Sendable {
    var shouldStop: Bool
    var stopReason: String?
}

func parsePreCompactCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<CompactHandlerData> {
    parseCompactCompleted(
        handler,
        runResult,
        turnId,
        eventLabel: "PreCompact",
        parseOutput: parsePreCompact
    )
}

func parsePostCompactCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<CompactHandlerData> {
    parseCompactCompleted(
        handler,
        runResult,
        turnId,
        eventLabel: "PostCompact",
        parseOutput: parsePostCompact
    )
}

func parseCompactCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?,
    eventLabel: String,
    parseOutput: (String) -> StatelessHookOutput?
) -> ParsedHandler<CompactHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed
    var shouldStop = false
    var stopReason: String?

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
            } else if let parsed = parseOutput(runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                _ = parsed.universal.suppressOutput
                if handler.canApplyControlEffects() {
                    if !parsed.universal.continueProcessing {
                        status = .stopped
                        shouldStop = true
                        stopReason = parsed.universal.stopReason
                        entries.append(HookOutputEntry(
                            kind: .stop,
                            text: parsed.universal.stopReason ?? "\(eventLabel) hook stopped execution"
                        ))
                    } else if let invalidReason = parsed.invalidReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                    }
                }
            } else if looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "hook returned invalid \(eventLabel) hook JSON output"
                ))
            }
        case let code?:
            status = .failed
            entries.append(HookOutputEntry(
                kind: .error,
                text: trimmedNonEmpty(runResult.stderr) ?? "hook exited with code \(code)"
            ))
        case nil:
            status = .failed
            entries.append(HookOutputEntry(
                kind: .error,
                text: "hook process terminated without an exit code"
            ))
        }
    }

    return ParsedHandler(
        completed: HookCompletedEvent(
            turnId: turnId,
            run: completedSummary(handler, runResult: runResult, status: status, entries: entries)
        ),
        data: CompactHandlerData(shouldStop: shouldStop, stopReason: stopReason),
        completionOrder: 0
    )
}
