//
//  pre_tool_use.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/pre_tool_use.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview, stdin JSON, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct PreToolUseRequest: Equatable, Sendable {
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
        toolInput: JSONValue
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
    }
}

public struct PreToolUseOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var shouldBlock: Bool
    public var blockReason: String?
    public var additionalContexts: [String]
    public var updatedInput: JSONValue?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        shouldBlock: Bool = false,
        blockReason: String? = nil,
        additionalContexts: [String] = [],
        updatedInput: JSONValue? = nil
    ) {
        self.hookEvents = hookEvents
        self.shouldBlock = shouldBlock
        self.blockReason = blockReason
        self.additionalContexts = additionalContexts
        self.updatedInput = updatedInput
    }
}

public func previewPreToolUse(
    handlers: [ConfiguredHandler],
    request: PreToolUseRequest
) -> [HookRunSummary] {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    return selectHandlersForMatcherInputs(
        handlers,
        eventName: .preToolUse,
        matcherInputs: inputs
    )
    .map { hookRunForToolUse(runningSummary($0), toolUseId: request.toolUseId) }
}

public func runPreToolUse(
    _ engine: ClaudeHooksEngine,
    request: PreToolUseRequest
) async -> PreToolUseOutcome {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    let matched = selectHandlersForMatcherInputs(
        engine.handlers,
        eventName: .preToolUse,
        matcherInputs: inputs
    )
    if matched.isEmpty {
        return PreToolUseOutcome()
    }

    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: commandInputJSON(request),
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        parse: parsePreToolUseCompleted
    )
    let shouldBlock = results.contains { $0.data.shouldBlock }
    let additionalContexts = await engine.commandRuntime.outputSpiller.maybeSpillAdditionalContexts(
        flattenAdditionalContexts(results.map(\.data.additionalContextsForModel))
    )
    return PreToolUseOutcome(
        hookEvents: results.map { hookCompletedForToolUse($0.completed, toolUseId: request.toolUseId) },
        shouldBlock: shouldBlock,
        blockReason: results.compactMap(\.data.blockReason).first,
        additionalContexts: additionalContexts,
        updatedInput: shouldBlock ? nil : latestUpdatedInput(results)
    )
}

func commandInputJSON(_ request: PreToolUseRequest) -> String {
    let subagent = SubagentCommandInputFields(request.subagent)
    return PreToolUseCommandInput(
        sessionId: request.sessionId.description,
        turnId: request.turnId,
        agentId: subagent.agentId,
        agentType: subagent.agentType,
        transcriptPath: .fromPath(request.transcriptPath),
        cwd: request.cwd.asPath,
        hookEventName: "PreToolUse",
        model: request.model,
        permissionMode: request.permissionMode,
        toolName: request.toolName,
        toolInput: request.toolInput,
        toolUseId: request.toolUseId
    ).encodedJSON()
}

struct PreToolUseHandlerData: Equatable, Sendable {
    var shouldBlock: Bool = false
    var blockReason: String?
    var additionalContextsForModel: [AdditionalContext] = []
    var updatedInput: JSONValue?
}

/// Chooses the rewrite from the hook that actually finished last.
func latestUpdatedInput(_ results: [ParsedHandler<PreToolUseHandlerData>]) -> JSONValue? {
    results
        .compactMap { result in
            result.data.updatedInput.map { (result.completionOrder, $0) }
        }
        .max { $0.0 < $1.0 }?
        .1
}

func parsePreToolUseCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<PreToolUseHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed
    var shouldBlock = false
    var blockReason: String?
    var additionalContextsForModel: [AdditionalContext] = []
    var updatedInput: JSONValue?

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
            } else if let parsed = parsePreToolUse(runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                if (!handler.canApplyControlEffects() || parsed.invalidReason == nil),
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
                    if let invalidReason = parsed.invalidReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                    } else if let reason = parsed.blockReason {
                        status = .blocked
                        shouldBlock = true
                        blockReason = reason
                        entries.append(HookOutputEntry(kind: .feedback, text: reason))
                    } else {
                        updatedInput = parsed.updatedInput
                    }
                }
            } else if looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "hook returned invalid pre-tool-use JSON output"
                ))
            }
        case 2 where handler.canApplyControlEffects():
            if let reason = trimmedNonEmpty(runResult.stderr) {
                status = .blocked
                shouldBlock = true
                blockReason = reason
                entries.append(HookOutputEntry(kind: .feedback, text: reason))
            } else {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "PreToolUse hook exited with code 2 but did not write a blocking reason to stderr"
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
        data: PreToolUseHandlerData(
            shouldBlock: shouldBlock,
            blockReason: blockReason,
            additionalContextsForModel: additionalContextsForModel,
            updatedInput: updatedInput
        ),
        completionOrder: 0
    )
}
