//
//  tasks_mod.swift
//  Sage
//
//  Port of codex-rs/core/src/tasks/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  SessionTask is the Codex lifecycle. RegularTask / ExploreTask keep the
//  existing ExecuteTurnLoop so AgentRuntime is not rewritten this wave.
//

import CodexCore
import CodexProtocol
import Foundation

let gracefulInterruptionTimeoutMs: UInt64 = 100

enum InterruptedTurnHistoryMarker: Equatable, Sendable {
    case disabled
    case contextualUser
    case developer

    static func fromConfig(_ config: Config, multiAgentVersion: MultiAgentVersion) -> InterruptedTurnHistoryMarker {
        guard config.agentInterruptMessageEnabled else { return .disabled }
        return multiAgentVersion == .v2 ? .developer : .contextualUser
    }
}

func interruptedTurnHistoryMarker(_ marker: InterruptedTurnHistoryMarker) -> ResponseItem? {
    switch marker {
    case .disabled:
        return nil
    case .contextualUser:
        return TurnAborted(guidance: TurnAborted.interruptedGuidance).asResponseItem()
    case .developer:
        return TurnAborted(guidance: TurnAborted.interruptedDeveloperGuidance).asResponseItem()
    }
}

protocol SessionTask: AnyObject, Sendable {
    var kind: TaskKind { get }
    func run(session: Session, context: TurnContext) async throws -> String?
}

typealias SessionTaskResult = String?
