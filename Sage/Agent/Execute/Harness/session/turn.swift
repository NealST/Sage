//
//  turn.swift
//  Sage
//
//  Port of codex-rs/core/src/session/turn.rs `run_turn` (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//
//  The Codex function samples, runs tool calls, and samples again while
//  `needs_follow_up` is set. Sage keeps the same shape: stream a completion,
//  hand tool calls to the existing batch runner, then sample again until the
//  model stops, the safety valve trips, or the user stops the turn.
//  Explore reuses this loop with a read-only tool set. Compaction, MCP
//  startup, and Guardian stay out of this file.
//

import Foundation

/// Shared sample → tools → sample loop. `RegularTask` and `ExploreTask` both use it.
@MainActor
protocol ExecuteTurnLoop: AnyObject {
    var canOfferMoreTools: Bool { get }
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
