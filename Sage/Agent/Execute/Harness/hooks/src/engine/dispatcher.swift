//
//  dispatcher.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/dispatcher.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Handler selection and running/completed summaries are faithful.
//  `execute_handlers` waits on CommandHookRuntime / MCP runner.
//

import CodexProtocol
import Foundation

public struct ParsedHandler<T> {
    public var completed: HookCompletedEvent
    public var data: T
    public var completionOrder: Int

    public init(completed: HookCompletedEvent, data: T, completionOrder: Int) {
        self.completed = completed
        self.data = data
        self.completionOrder = completionOrder
    }
}

public func selectHandlers(
    _ handlers: [ConfiguredHandler],
    eventName: HookEventName,
    matcherInput: String?
) -> [ConfiguredHandler] {
    let inputs = matcherInput.map { [$0] } ?? []
    return selectHandlersForMatcherInputs(handlers, eventName: eventName, matcherInputs: inputs)
}

public func selectHandlersForMatcherInputs(
    _ handlers: [ConfiguredHandler],
    eventName: HookEventName,
    matcherInputs: [String]
) -> [ConfiguredHandler] {
    handlers.filter { handler in
        guard handler.eventName == eventName else { return false }
        switch eventName {
        case .preToolUse, .permissionRequest, .postToolUse, .sessionStart, .sessionEnd,
             .subagentStart, .subagentStop, .preCompact, .postCompact:
            if matcherInputs.isEmpty {
                return matchesMatcher(handler.matcher, input: nil)
            }
            return matcherInputs.contains { matchesMatcher(handler.matcher, input: $0) }
        case .userPromptSubmit, .stop, .interrupt:
            return true
        }
    }
}

public func runningSummary(_ handler: ConfiguredHandler) -> HookRunSummary {
    guard case .local(let sourcePath) = handler.sourcePath else {
        preconditionFailure("executor-scoped hooks do not produce public hook summaries")
    }
    return HookRunSummary(
        builtin: handler.builtin,
        id: handler.runId(),
        eventName: handler.eventName,
        handlerType: handler.handlerType(),
        executionMode: handler.executionMode(),
        scope: scopeForEvent(handler.eventName),
        sourcePath: sourcePath,
        source: handler.source,
        displayOrder: handler.displayOrder,
        status: .running,
        statusMessage: handler.statusMessage,
        startedAt: Int64(Date().timeIntervalSince1970)
    )
}

public func completedSummary(
    _ handler: ConfiguredHandler,
    runResult: HandlerRunResult,
    status: HookRunStatus,
    entries: [HookOutputEntry]
) -> HookRunSummary {
    var summary = runningSummary(handler)
    summary.status = status
    summary.startedAt = runResult.startedAt
    summary.completedAt = runResult.completedAt
    summary.durationMs = runResult.durationMs
    summary.entries = entries
    return summary
}

public func hookExecutionModeLabel(_ mode: HookExecutionMode) -> String {
    switch mode {
    case .sync: return "sync"
    case .async: return "async"
    }
}

public func hookHandlerTypeLabel(_ type: HookHandlerType) -> String {
    switch type {
    case .command: return "command"
    case .mcpTool: return "mcp_tool"
    case .prompt: return "prompt"
    case .agent: return "agent"
    }
}

func scopeForEvent(_ eventName: HookEventName) -> HookScope {
    switch eventName {
    case .sessionStart, .sessionEnd, .subagentStart:
        return .thread
    case .preToolUse, .permissionRequest, .postToolUse, .preCompact, .postCompact,
         .userPromptSubmit, .subagentStop, .stop, .interrupt:
        return .turn
    }
}

func serializationFailureHookEvents(
    handlers: [ConfiguredHandler],
    turnId: String?,
    errorMessage: String
) -> [HookCompletedEvent] {
    handlers.compactMap { handler in
        guard case .local = handler.sourcePath else { return nil }
        var run = runningSummary(handler)
        run.status = .failed
        run.completedAt = run.startedAt
        run.durationMs = 0
        run.entries = [HookOutputEntry(kind: .error, text: errorMessage)]
        return HookCompletedEvent(turnId: turnId, run: run)
    }
}

func serializationFailureHookEventsForToolUse(
    handlers: [ConfiguredHandler],
    turnId: String?,
    errorMessage: String,
    toolUseId: String
) -> [HookCompletedEvent] {
    serializationFailureHookEvents(
        handlers: handlers,
        turnId: turnId,
        errorMessage: errorMessage
    )
    .map { hookCompletedForToolUse($0, toolUseId: toolUseId) }
}

public func appendAdditionalContext(
    entries: inout [HookOutputEntry],
    additionalContextsForModel: inout [AdditionalContext],
    handler: ConfiguredHandler,
    additionalContext: String
) {
    entries.append(HookOutputEntry(kind: .context, text: additionalContext))
    additionalContextsForModel.append(
        AdditionalContext(text: additionalContext, limit: handler.additionalContextLimit)
    )
}
