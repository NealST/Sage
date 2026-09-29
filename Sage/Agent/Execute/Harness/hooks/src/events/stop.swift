//
//  stop.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/stop.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview filtering, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct StopRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var requestMetadata: [String: JSONValue]?
    public var stopHookActive: Bool
    public var lastAssistantMessage: String?
    public var target: StopHookTarget

    public init(
        sessionId: ThreadId,
        turnId: String,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        requestMetadata: [String: JSONValue]? = nil,
        stopHookActive: Bool,
        lastAssistantMessage: String? = nil,
        target: StopHookTarget
    ) {
        self.sessionId = sessionId
        self.turnId = turnId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.requestMetadata = requestMetadata
        self.stopHookActive = stopHookActive
        self.lastAssistantMessage = lastAssistantMessage
        self.target = target
    }
}

public enum StopHookTarget: Equatable, Sendable {
    case stop
    case memoryConsolidation
    case subagentStop(agentId: String, agentType: String, agentTranscriptPath: String?)

    public func eventName() -> HookEventName {
        switch self {
        case .stop, .memoryConsolidation: return .stop
        case .subagentStop: return .subagentStop
        }
    }

    public func matcherInput() -> String? {
        switch self {
        case .stop, .memoryConsolidation: return nil
        case .subagentStop(_, let agentType, _): return agentType
        }
    }

    public func matchedHandlers(_ handlers: [ConfiguredHandler]) -> [ConfiguredHandler] {
        selectHandlers(handlers, eventName: eventName(), matcherInput: matcherInput())
            .filter { handler in
                guard case .memoryConsolidation = self else { return true }
                if case .executorScoped = handler.sourcePath { return true }
                switch handler.source {
                case .user, .project, .sessionFlags, .plugin:
                    return false
                default:
                    return true
                }
            }
    }
}

public struct StopOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldStop: Bool
    public var stopReason: String?
    public var shouldBlock: Bool
    public var blockReason: String?
    public var continuationFragments: [HookPromptFragment]

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldStop: Bool = false,
        stopReason: String? = nil,
        shouldBlock: Bool = false,
        blockReason: String? = nil,
        continuationFragments: [HookPromptFragment] = []
    ) {
        self.hookEvents = hookEvents
        self.shouldStop = shouldStop
        self.stopReason = stopReason
        self.shouldBlock = shouldBlock
        self.blockReason = blockReason
        self.continuationFragments = continuationFragments
    }
}

public func previewStop(
    handlers: [ConfiguredHandler],
    request: StopRequest
) -> [HookRunSummary] {
    request.target.matchedHandlers(handlers)
        .filter { if case .local = $0.sourcePath { return true }; return false }
        .map(runningSummary)
}

public func runStop(
    _ engine: ClaudeHooksEngine,
    request: StopRequest
) async -> StopOutcome {
    let matched = request.target.matchedHandlers(engine.handlers)
    if matched.isEmpty {
        return StopOutcome()
    }

    // Memory workers terminate on managed rejection rather than continuing the turn,
    // so their executor cleanup must also run when a managed hook blocks completion.
    var executorCleanup: [ConfiguredHandler] = []
    var localMatched: [ConfiguredHandler] = []
    for handler in matched {
        if case .memoryConsolidation = request.target, case .executorScoped = handler.sourcePath {
            executorCleanup.append(handler)
        } else {
            localMatched.append(handler)
        }
    }

    let inputJSON = commandInputJSON(request)
    let results = await executeHandlers(
        engine: engine,
        handlers: localMatched,
        inputJSON: inputJSON,
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        metadata: request.requestMetadata,
        parse: parseStopCompleted
    )
    if !executorCleanup.isEmpty {
        _ = await executeHandlers(
            engine: engine,
            handlers: executorCleanup,
            inputJSON: inputJSON,
            cwd: request.cwd.asPath,
            turnId: request.turnId,
            metadata: request.requestMetadata,
            parse: parseStopCompleted
        )
    }

    let aggregate = aggregateStopResults(results.map(\.data))
    return StopOutcome(
        hookEvents: results.map(\.completed),
        shouldStop: aggregate.shouldStop,
        stopReason: aggregate.stopReason,
        shouldBlock: aggregate.shouldBlock,
        blockReason: aggregate.blockReason,
        continuationFragments: aggregate.continuationFragments
    )
}

func commandInputJSON(_ request: StopRequest) -> String {
    switch request.target {
    case .stop, .memoryConsolidation:
        return StopCommandInput(
            sessionId: request.sessionId.description,
            turnId: request.turnId,
            transcriptPath: .fromPath(request.transcriptPath),
            cwd: request.cwd.asPath,
            hookEventName: "Stop",
            model: request.model,
            permissionMode: request.permissionMode,
            stopHookActive: request.stopHookActive,
            lastAssistantMessage: .fromString(request.lastAssistantMessage)
        ).encodedJSON()
    case .subagentStop(let agentId, let agentType, let agentTranscriptPath):
        return SubagentStopCommandInput(
            sessionId: request.sessionId.description,
            turnId: request.turnId,
            transcriptPath: .fromPath(request.transcriptPath),
            agentTranscriptPath: .fromPath(agentTranscriptPath),
            cwd: request.cwd.asPath,
            hookEventName: "SubagentStop",
            model: request.model,
            permissionMode: request.permissionMode,
            stopHookActive: request.stopHookActive,
            agentId: agentId,
            agentType: agentType,
            lastAssistantMessage: .fromString(request.lastAssistantMessage)
        ).encodedJSON()
    }
}

struct StopHandlerData: Equatable, Sendable {
    var shouldStop: Bool = false
    var stopReason: String?
    var shouldBlock: Bool = false
    var blockReason: String?
    var continuationFragments: [HookPromptFragment] = []
}

func parseStopCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<StopHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed
    var shouldStop = false
    var stopReason: String?
    var shouldBlock = false
    var blockReason: String?
    var continuationPrompt: String?
    let hookEventName = stopHookEventName(handler.eventName)

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
            } else if let parsed = parseStopOutput(hookEventName, stdout: runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                _ = parsed.universal.suppressOutput
                if handler.canApplyControlEffects() {
                    if !parsed.universal.continueProcessing {
                        status = .stopped
                        shouldStop = true
                        stopReason = parsed.universal.stopReason
                        if let stopReasonText = parsed.universal.stopReason {
                            entries.append(HookOutputEntry(kind: .stop, text: stopReasonText))
                        }
                    } else if let invalidBlockReason = parsed.invalidBlockReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidBlockReason))
                    } else if parsed.shouldBlock,
                              let reason = parsed.reason.flatMap(trimmedNonEmpty)
                    {
                        status = .blocked
                        shouldBlock = true
                        blockReason = reason
                        continuationPrompt = reason
                        entries.append(HookOutputEntry(kind: .feedback, text: reason))
                    }
                }
            } else if handler.canApplyControlEffects() || looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(kind: .error, text: invalidStopJSONMessage(hookEventName)))
            }
        case 2 where handler.canApplyControlEffects():
            if let reason = trimmedNonEmpty(runResult.stderr) {
                status = .blocked
                shouldBlock = true
                blockReason = reason
                continuationPrompt = reason
                entries.append(HookOutputEntry(kind: .feedback, text: reason))
            } else {
                status = .failed
                entries.append(HookOutputEntry(kind: .error, text: missingStopStderrMessage(hookEventName)))
            }
        case let exitCode?:
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: "hook exited with code \(exitCode)"))
        case nil:
            status = .failed
            entries.append(HookOutputEntry(kind: .error, text: "hook exited without a status code"))
        }
    }

    let completed = HookCompletedEvent(
        turnId: turnId,
        run: completedSummary(handler, runResult: runResult, status: status, entries: entries)
    )
    let continuationFragments = continuationPrompt.map {
        [HookPromptFragment.fromSingleHook(text: $0, hookRunId: completed.run.id)]
    } ?? []

    return ParsedHandler(
        completed: completed,
        data: StopHandlerData(
            shouldStop: shouldStop,
            stopReason: stopReason,
            shouldBlock: shouldBlock,
            blockReason: blockReason,
            continuationFragments: continuationFragments
        ),
        completionOrder: 0
    )
}

func aggregateStopResults(_ results: [StopHandlerData]) -> StopHandlerData {
    let shouldStop = results.contains { $0.shouldStop }
    let stopReason = results.compactMap(\.stopReason).first
    let shouldBlock = !shouldStop && results.contains { $0.shouldBlock }
    let blockReason = shouldBlock
        ? joinTextChunks(results.compactMap(\.blockReason))
        : nil
    let continuationFragments = shouldBlock
        ? results.filter(\.shouldBlock).flatMap(\.continuationFragments)
        : []
    return StopHandlerData(
        shouldStop: shouldStop,
        stopReason: stopReason,
        shouldBlock: shouldBlock,
        blockReason: blockReason,
        continuationFragments: continuationFragments
    )
}

private func stopHookEventName(_ eventName: HookEventName) -> HookEventName {
    switch eventName {
    case .stop, .subagentStop:
        return eventName
    default:
        preconditionFailure("expected stop hook event, got \(eventName)")
    }
}

private func parseStopOutput(_ eventName: HookEventName, stdout: String) -> StopOutput? {
    switch eventName {
    case .stop:
        return parseStop(stdout)
    case .subagentStop:
        return parseSubagentStop(stdout)
    default:
        preconditionFailure("expected stop hook event, got \(eventName)")
    }
}

private func invalidStopJSONMessage(_ eventName: HookEventName) -> String {
    switch eventName {
    case .stop:
        return "hook returned invalid stop hook JSON output"
    case .subagentStop:
        return "hook returned invalid subagent stop hook JSON output"
    default:
        preconditionFailure("expected stop hook event, got \(eventName)")
    }
}

private func missingStopStderrMessage(_ eventName: HookEventName) -> String {
    switch eventName {
    case .stop:
        return "Stop hook exited with code 2 but did not write a continuation prompt to stderr"
    case .subagentStop:
        return "SubagentStop hook exited with code 2 but did not write a continuation prompt to stderr"
    default:
        preconditionFailure("expected stop hook event, got \(eventName)")
    }
}
