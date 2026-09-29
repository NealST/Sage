//
//  interrupt.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/events/interrupt.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Request/outcome types, preview, stdin JSON, `run`, and parse_completed
//  are ported. Process spawn is Foundation.Process.
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

public func runInterrupt(_ engine: ClaudeHooksEngine, request: InterruptRequest) async -> InterruptOutcome {
    let matched = selectHandlers(engine.handlers, eventName: .interrupt, matcherInput: nil)
    if matched.isEmpty {
        return InterruptOutcome()
    }

    let inputJSON = commandInputJSON(request)
    let results = await executeHandlers(
        engine: engine,
        handlers: matched,
        inputJSON: inputJSON,
        cwd: request.cwd.asPath,
        turnId: request.turnId,
        metadata: request.requestMetadata,
        parse: parseInterruptCompleted
    )
    return InterruptOutcome(hookEvents: results.map(\.completed))
}

func commandInputJSON(_ request: InterruptRequest) -> String {
    InterruptCommandInput(
        sessionId: request.sessionId.description,
        turnId: request.turnId,
        transcriptPath: .fromPath(request.transcriptPath),
        cwd: request.cwd.asPath,
        hookEventName: "Interrupt",
        model: request.model,
        permissionMode: request.permissionMode
    ).encodedJSON()
}

struct InterruptHandlerData: Equatable, Sendable {}

func parseInterruptCompleted(
    _ handler: ConfiguredHandler,
    _ runResult: HandlerRunResult,
    _ turnId: String?
) -> ParsedHandler<InterruptHandlerData> {
    var entries: [HookOutputEntry] = []
    var status = HookRunStatus.completed

    if let error = runResult.error {
        status = .failed
        entries.append(HookOutputEntry(kind: .error, text: error))
    } else {
        switch runResult.exitCode {
        case 0:
            let trimmedStdout = runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedStdout.isEmpty {
            } else if let parsed = parseInterrupt(runResult.stdout) {
                if let systemMessage = parsed.systemMessage {
                    entries.append(HookOutputEntry(kind: .warning, text: systemMessage))
                }
            } else {
                status = .failed
                let text = looksLikeJSON(runResult.stdout)
                    ? "hook returned invalid interrupt hook JSON output"
                    : "Interrupt hook returned non-JSON stdout"
                entries.append(HookOutputEntry(kind: .error, text: text))
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
        data: InterruptHandlerData(),
        completionOrder: 0
    )
}
