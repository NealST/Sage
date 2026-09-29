//
//  stop.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/stop.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview filtering are faithful. `run` waits
//  on the command runner.
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
) async throws -> StopOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("stop hook run waits on CommandHookRuntime")
}
