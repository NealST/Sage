//
//  interrupt.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/interrupt.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types and preview are faithful. `run` waits on the
//  command runner.
//

import CodexProtocol
import CodexUtils
import Foundation

public struct InterruptRequest: Equatable, Sendable {
    public var sessionId: ThreadId
    public var turnId: String
    public var cwd: AbsolutePathBuf
    public var transcriptPath: String?
    public var model: String
    public var permissionMode: String
    public var requestMetadata: [String: JSONValue]?

    public init(
        sessionId: ThreadId,
        turnId: String,
        cwd: AbsolutePathBuf,
        transcriptPath: String? = nil,
        model: String,
        permissionMode: String,
        requestMetadata: [String: JSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.turnId = turnId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.model = model
        self.permissionMode = permissionMode
        self.requestMetadata = requestMetadata
    }
}

public struct InterruptOutcome: Equatable, Sendable {
    public var hookEvents: [HookCompletedEvent]

    public init(hookEvents: [HookCompletedEvent] = []) {
        self.hookEvents = hookEvents
    }
}

public func previewInterrupt(handlers: [ConfiguredHandler]) -> [HookRunSummary] {
    selectHandlers(handlers, eventName: .interrupt, matcherInput: nil)
        .filter { if case .local = $0.sourcePath { return true }; return false }
        .map(runningSummary)
}

public func runInterrupt(_ engine: ClaudeHooksEngine, request: InterruptRequest) async throws -> InterruptOutcome {
    _ = (engine, request)
    throw CodexErr.unsupportedOperation("interrupt hook run waits on CommandHookRuntime")
}
