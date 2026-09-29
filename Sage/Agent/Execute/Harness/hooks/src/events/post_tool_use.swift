//
//  post_tool_use.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/post_tool_use.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview, stdin JSON, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct PostToolUseRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var subagent: SubagentHookContext?
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var matcherAliases: [String]
    public var toolUseId: String
    public var toolInput: JSONValue
    public var toolResponse: JSONValue

    public init(
        sessionId: ThreadId,
        turnId: String,
        subagent: SubagentHookContext? = nil,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        toolName: String,
        matcherAliases: [String] = [],
        toolUseId: String,
        toolInput: JSONValue,
        toolResponse: JSONValue
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
        self.toolUseId = toolUseId
        self.toolInput = toolInput
        self.toolResponse = toolResponse
    }
}

public struct PostToolUseOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldBlock: Bool
    public var additionalContexts: [String]
    public var feedbackMessage: String?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldBlock: Bool = false,
        additionalContexts: [String] = [],
        feedbackMessage: String? = nil
    ) {
        self.hookEvents = hookEvents
        self.shouldBlock = shouldBlock
        self.additionalContexts = additionalContexts
        self.feedbackMessage = feedbackMessage
    }
}

public func previewPostToolUse(
    handlers: [ConfiguredHandler],
    request: PostToolUseRequest
) -> [HookRunSummary] {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    return selectHandlersForMatcherInputs(
        handlers,
        eventName: .postToolUse,
        matcherInputs: inputs
    )
    .map { hookRunForToolUse(runningSummary($0), toolUseId: request.toolUseId) }
}

public func runPostToolUse(
    _ engine: ClaudeHooksEngine,
    request: PostToolUseRequest
) async -> PostToolUseOutcome {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    let matched = selectHandlersForMatcherInputs(
        engine.handlers,
        eventName: .postToolUse,
        matcherInputs: inputs
    )
    if matched.isEmpty {
        return PostToolUseOutcome()
    }

    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: commandInputJSON(request),
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        parse: parsePostToolUseCompleted
    )
    let additionalContexts = await engine.commandRuntime.outputSpiller.maybeSpillAdditionalContexts(
        flattenAdditionalContexts(results.map(\.data.additionalContextsForModel))
    )
    return PostToolUseOutcome(
        hookEvents: results.map { hookCompletedForToolUse($0.completed, toolUseId: request.toolUseId) },
        shouldBlock: results.contains { $0.data.shouldBlock },
        additionalContexts: additionalContexts,
        feedbackMessage: joinTextChunks(results.flatMap(\.data.feedbackMessagesForModel))
    )
}

func commandInputJSON(_ request: PostToolUseRequest) -> String {
    let subagent = SubagentCommandInputFields(request.subagent)
    return PostToolUseCommandInput(
        sessionId: request.sessionId.description,
        turnId: request.turnId,
        agentId: subagent.agentId,
        agentType: subagent.agentType,
        transcriptPath: .fromPath(request.transcriptPath),
        cwd: request.cwd.asPath,
        hookEventName: "PostToolUse",
        model: request.model,
        permissionMode: request.permissionMode,
        toolName: request.toolName,
        toolInput: request.toolInput,
        toolResponse: request.toolResponse,
        toolUseId: request.toolUseId
    ).encodedJSON()
}

struct PostToolUseHandlerData: Equatable, Sendable {
    var shouldBlock: Bool = false
    var additionalContextsForModel: [AdditionalContext] = []
    var feedbackMessagesForModel: [String] = []
}

func parsePostToolUseCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<PostToolUseHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed
    var shouldBlock = false
    var additionalContextsForModel: [AdditionalContext] = []
    var feedbackMessagesForModel: [String] = []

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
            } else if let parsed = parsePostToolUse(runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                if (!handler.canApplyControlEffects()
                    || parsed.invalidReason == nil && parsed.invalidBlockReason == nil),
                   let additionalContext = parsed.additionalContext
                {
                    appendAdditionalContext(
                        entries: &entries,
                        additionalContextsForModel: &additionalContextsForModel,
                        handler: handler,
                        additionalContext: additionalContext
                    )
                }
                if handler.canApplyControlEffects() {
                    if !parsed.universal.continueProcessing {
                        status = .stopped
                        let stopText = parsed.universal.stopReason ?? "PostToolUse hook stopped execution"
                        entries.append(HookOutputEntry(kind: .stop, text: stopText))
                        let modelFeedback = parsed.reason.flatMap(trimmedNonEmpty) ?? stopText
                        feedbackMessagesForModel.append(modelFeedback)
                    } else if let invalidReason = parsed.invalidReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                    } else if let invalidBlockReason = parsed.invalidBlockReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidBlockReason))
                    } else if parsed.shouldBlock {
                        status = .blocked
                        shouldBlock = true
                        if let reason = parsed.reason {
                            entries.append(HookOutputEntry(kind: .feedback, text: reason))
                            feedbackMessagesForModel.append(reason)
                        }
                    }
                }
            } else if looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "hook returned invalid post-tool-use JSON output"
                ))
            }
        case 2 where handler.canApplyControlEffects():
            if let reason = trimmedNonEmpty(runResult.stderr) {
                status = .blocked
                shouldBlock = true
                entries.append(HookOutputEntry(kind: .feedback, text: reason))
                feedbackMessagesForModel.append(reason)
            } else {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "PostToolUse hook exited with code 2 but did not write feedback to stderr"
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
        data: PostToolUseHandlerData(
            shouldBlock: shouldBlock,
            additionalContextsForModel: additionalContextsForModel,
            feedbackMessagesForModel: feedbackMessagesForModel
        ),
        completionOrder: 0
    )
}
