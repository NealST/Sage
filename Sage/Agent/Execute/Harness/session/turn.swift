//
//  turn.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: partial
//
//  Skeleton of `run_turn` only; the full 3,105-line turn loop is Phase 5.
//
//  Codex `run_turn` asks the model, runs tool calls, then asks again while
//  the model still wants tools. Before each question it compacts when the
//  window is full and starts the MCP servers the turn needs. Tool hooks run
//  when those calls execute, still inside this loop. Guardian stays out.
//

import Foundation

/// Shared sample → tools → sample loop. `RegularTask` and `ExploreTask` both use it.
@MainActor
protocol ExecuteTurnLoop: AnyObject {
    var canOfferMoreTools: Bool { get }
    /// Compact, then connect MCP servers, before this sample. Tool hooks run in `consume`.
    func willSample(includeTools: Bool) async
    func sample(includeTools: Bool) async throws -> ModelTurn
    func consume(_ turn: ModelTurn) async -> Turn.StepResult
    func didCancel() async
    func didFail(_ error: Error) async
    func pauseForToolRoundLimit() async
}

enum Turn {
    enum StepResult {
        /// Final answer, approval pause, safety valve, or a failed persist.
        case finished
        /// Tool output is in the transcript. Sample again.
        case needsFollowUp
    }

    @MainActor
    static func run(_ task: some ExecuteTurnLoop, includeTools: Bool) async {
        var includeTools = includeTools
        while !Task.isCancelled {
            await task.willSample(includeTools: includeTools)
            let turn: ModelTurn
            do {
                try Task.checkCancellation()
                turn = try await task.sample(includeTools: includeTools)
                try Task.checkCancellation()
            } catch is CancellationError {
                await task.didCancel()
                return
            } catch {
                await task.didFail(error)
                return
            }

            switch await task.consume(turn) {
            case .finished:
                return
            case .needsFollowUp:
                includeTools = true
                guard task.canOfferMoreTools else {
                    await task.pauseForToolRoundLimit()
                    return
                }
            }
        }
    }
}
