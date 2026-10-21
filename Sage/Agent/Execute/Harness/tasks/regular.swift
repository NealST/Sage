//
//  regular.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/regular.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `RegularSessionTask` is rust `RegularTask`: emit start, consume
//  prewarm, then `runTurn` until the input queue is idle or a terminal
//  error is set. The Sage-side execute glue lives in
//  `Agent/Execute/ExecuteTask.swift` (`RegularTask`).
//

import SageAsyncUtils
import SageCore
import SageProtocol
import SageThreadStore
import Foundation

/// Sage `RegularTask`.
final class RegularSessionTask: SessionTask, @unchecked Sendable {
    var kind: TaskKind { .regular }
    /// Test seam: runs after each `runTurn` so pending input can be queued
    /// for the rust outer loop.
    var afterRunTurn: (() -> Void)?

    init() {}

    func run(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async throws -> String? {
        if session.activeTurn == nil {
            session.activeTurn = ActiveTurn(
                task: RunningTask(kind: .regular, turnContext: context),
                turnState: TurnState()
            )
        } else if session.activeTurn?.task == nil {
            session.activeTurn?.task = RunningTask(kind: .regular, turnContext: context)
        }
        session.emitTurnStarted(context)

        let prewarmedClientSession = await prepareRunTurn(
            session: session,
            context: context,
            input: input,
            cancellationToken: cancellationToken
        )
        switch prewarmedClientSession {
        case .cancelled:
            return nil
        case .unavailable, .ready:
            break
        }

        var nextInput = input
        var prewarmed = prewarmedClientSession.readySession
        var mcpStartupRequirements = McpStartupRequirements()
        while true {
            let lastAgentMessage = try await runTurn(
                sess: session,
                turnContext: context,
                input: &nextInput,
                mcpStartupRequirements: &mcpStartupRequirements,
                prewarmedClientSession: prewarmed,
                cancellationToken: cancellationToken.childToken()
            )
            prewarmed = nil
            afterRunTurn?()
            if cancellationToken.isCancelled {
                throw SageErr(details: .turnAborted)
            }
            if context.terminalError != nil {
                return lastAgentMessage
            }
            if !session.inputQueue.hasPendingInput(session.activeTurn) {
                return lastAgentMessage
            }
            nextInput = []
        }
    }

    private func prepareRunTurn(
        session: Session,
        context: TurnContext,
        input: [SessionTurnInput],
        cancellationToken: CancellationToken
    ) async -> SessionStartupPrewarmResolution {
        await session.emitTurnStartLifecycle(
            context,
            tokenUsageAtTurnStart: nil,
            phase: .regularTaskStart
        )
        session.requestMcpRuntimeReprojection()
        if cancellationToken.isCancelled {
            _ = await runHooksAndRecordInputs(
                sess: session,
                turnContext: context,
                modelInfo: context.captureCurrentModelInfo(),
                input: input,
                persistContext: .standard
            )
            return .cancelled
        }
        session.setServerReasoningIncluded(false)
        let resolution = await session.consumeStartupPrewarm(
            cancellationToken: cancellationToken
        )
        if case .cancelled = resolution {
            _ = await runHooksAndRecordInputs(
                sess: session,
                turnContext: context,
                modelInfo: context.captureCurrentModelInfo(),
                input: input,
                persistContext: .standard
            )
        }
        return resolution
    }
}

private extension SessionStartupPrewarmResolution {
    var readySession: ModelClientSession? {
        if case .ready(let session) = self { return session }
        return nil
    }
}

