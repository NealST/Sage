//
//  user_prompt_submit.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/user_prompt_submit.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview, stdin JSON, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
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
) async -> UserPromptSubmitOutcome {
    let matched = selectHandlers(engine.handlers, eventName: .userPromptSubmit, matcherInput: nil)
    if matched.isEmpty {
        return UserPromptSubmitOutcome()
    }

    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: commandInputJSON(request),
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        parse: parseUserPromptSubmitCompleted
    )
    let additionalContexts = await engine.commandRuntime.outputSpiller.maybeSpillAdditionalContexts(
        flattenAdditionalContexts(results.map(\.data.additionalContextsForModel))
    )
    return UserPromptSubmitOutcome(
        hookEvents: results.map(\.completed),
        shouldStop: results.contains { $0.data.shouldStop },
        stopReason: results.compactMap(\.data.stopReason).first,
        additionalContexts: additionalContexts
    )
}

func commandInputJSON(_ request: UserPromptSubmitRequest) -> String {
    let subagent = SubagentCommandInputFields(request.subagent)
    return UserPromptSubmitCommandInput(
        sessionId: request.sessionId.description,
        turnId: request.turnId,
        agentId: subagent.agentId,
        agentType: subagent.agentType,
        transcriptPath: request.transcriptPath,
        cwd: request.cwd.asPath,
        model: request.model,
        permissionMode: request.permissionMode,
        prompt: request.prompt
    ).encodedJSON()
}

struct UserPromptSubmitHandlerData: Equatable, Sendable {
    var shouldStop: Bool
    var stopReason: String?
    var additionalContextsForModel: [AdditionalContext]
}

func parseUserPromptSubmitCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<UserPromptSubmitHandlerData> {
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
            } else if let parsed = parseUserPromptSubmit(runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                if (!handler.canApplyControlEffects() || parsed.invalidBlockReason == nil),
                   let additionalContext = parsed.additionalContext
                {
                    appendAdditionalContext(
                        entries: &entries,
                        additionalContextsForModel: &additionalContextsForModel,
                        handler: handler,
                        additionalContext: additionalContext
                    )
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
                    } else if parsed.shouldBlock {
                        status = .blocked
                        shouldStop = true
                        stopReason = parsed.reason
                        if let reason = parsed.reason {
                            entries.append(HookOutputEntry(kind: .feedback, text: reason))
                        }
                    }
                }
            } else if looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "hook returned invalid user prompt submit JSON output"
                ))
            } else {
                appendAdditionalContext(
                    entries: &entries,
                    additionalContextsForModel: &additionalContextsForModel,
                    handler: handler,
                    additionalContext: trimmedStdout
                )
            }
        case 2 where handler.canApplyControlEffects():
            if let reason = trimmedNonEmpty(runResult.stderr) {
                status = .blocked
                shouldStop = true
                stopReason = reason
                entries.append(HookOutputEntry(kind: .feedback, text: reason))
            } else {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "UserPromptSubmit hook exited with code 2 but did not write a blocking reason to stderr"
                ))
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
        data: UserPromptSubmitHandlerData(
            shouldStop: shouldStop,
            stopReason: stopReason,
            additionalContextsForModel: additionalContextsForModel
        ),
        completionOrder: 0
    )
}
