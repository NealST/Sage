//
//  permission_request.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/permission_request.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview, stdin JSON, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
//  `PermissionRequestDecision` is shared with the output parser (one Swift
//  module; rust keeps two identical types).
//

import CodexProtocol
import CodexUtils
import Foundation

public struct PermissionRequestRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var subagent: SubagentHookContext?
    public var cwd: String
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var toolName: String
    public var matcherAliases: [String]
    public var runIdSuffix: String
    public var toolInput: JSONValue

    public init(
        sessionId: ThreadId,
        turnId: String,
        subagent: SubagentHookContext? = nil,
        cwd: String,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        toolName: String,
        matcherAliases: [String] = [],
        runIdSuffix: String,
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
        self.runIdSuffix = runIdSuffix
        self.toolInput = toolInput
    }
}

public struct PermissionRequestOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]
    public var decision: PermissionRequestDecision?

    public init(
        hookEvents: [HookCompletedEvent] = [],
        decision: PermissionRequestDecision? = nil
    ) {
        self.hookEvents = hookEvents
        self.decision = decision
    }
}

public func previewPermissionRequest(
    handlers: [ConfiguredHandler],
    request: PermissionRequestRequest
) -> [HookRunSummary] {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    return selectHandlersForMatcherInputs(
        handlers,
        eventName: .permissionRequest,
        matcherInputs: inputs
    )
    .map { hookRunForToolUse(runningSummary($0), toolUseId: request.runIdSuffix) }
}

public func runPermissionRequest(
    _ engine: ClaudeHooksEngine,
    request: PermissionRequestRequest
) async -> PermissionRequestOutcome {
    let inputs = matcherInputs(toolName: request.toolName, matcherAliases: request.matcherAliases)
    let matched = selectHandlersForMatcherInputs(
        engine.handlers,
        eventName: .permissionRequest,
        matcherInputs: inputs
    )
    if matched.isEmpty {
        return PermissionRequestOutcome()
    }

    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: commandInputJSON(request),
        cwd: request.cwd,
        turnId: request.turnId,
        parse: parsePermissionRequestCompleted
    )
    return PermissionRequestOutcome(
        hookEvents: results.map { hookCompletedForToolUse($0.completed, toolUseId: request.runIdSuffix) },
        decision: resolvePermissionRequestDecision(results.compactMap(\.data.decision))
    )
}

func commandInputJSON(_ request: PermissionRequestRequest) -> String {
    let subagent = SubagentCommandInputFields(request.subagent)
    return PermissionRequestCommandInput(
        sessionId: request.sessionId.description,
        turnId: request.turnId,
        agentId: subagent.agentId,
        agentType: subagent.agentType,
        transcriptPath: .fromPath(request.transcriptPath),
        cwd: request.cwd,
        hookEventName: "PermissionRequest",
        model: request.model,
        permissionMode: request.permissionMode,
        toolName: request.toolName,
        toolInput: request.toolInput
    ).encodedJSON()
}

struct PermissionRequestHandlerData: Equatable, Sendable {
    var decision: PermissionRequestDecision?
}

/// Any deny wins immediately; otherwise keep the last allow.
func resolvePermissionRequestDecision(
    _ decisions: [PermissionRequestDecision]
) -> PermissionRequestDecision? {
    var resolvedAllow: PermissionRequestDecision?
    for decision in decisions {
        switch decision {
        case .allow:
            resolvedAllow = .allow
        case .deny:
            return decision
        }
    }
    return resolvedAllow
}

func parsePermissionRequestCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<PermissionRequestHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed
    var decision: PermissionRequestDecision?

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
            } else if let parsed = parsePermissionRequest(runResult.stdout) {
                if let systemMessage = parsed.universal.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
                if handler.canApplyControlEffects() {
                    if let invalidReason = parsed.invalidReason {
                        status = .failed
                        entries.append(HookOutputEntry(kind: .error, text: invalidReason))
                    } else if let parsedDecision = parsed.decision {
                        switch parsedDecision {
                        case .allow:
                            decision = .allow
                        case .deny(let message):
                            status = .blocked
                            entries.append(HookOutputEntry(kind: .feedback, text: message))
                            decision = .deny(message: message)
                        }
                    }
                }
            } else if looksLikeJSON(runResult.stdout) {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "hook returned invalid permission-request JSON output"
                ))
            }
        case 2 where handler.canApplyControlEffects():
            if let message = trimmedNonEmpty(runResult.stderr) {
                status = .blocked
                entries.append(HookOutputEntry(kind: .feedback, text: message))
                decision = .deny(message: message)
            } else {
                status = .failed
                entries.append(HookOutputEntry(
                    kind: .error,
                    text: "PermissionRequest hook exited with code 2 but did not write a denial reason to stderr"
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
        data: PermissionRequestHandlerData(decision: decision),
        completionOrder: 0
    )
}
