//
//  turn_input.swift
//  CodexCore
//
//  Port of codex-rs/core/src/session/turn_input.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Decides whether submitted input starts a turn, steers the active turn,
//  or is rejected, then builds the queued items. Thread-settings preview
//  and rollout persistence stay out; `ThreadSession` applies the mode
//  override only after the input is accepted. Realtime text routing stays
//  deferred with the voice subset.
//

import CodexContextFragments
import CodexProtocol
import Foundation

public enum TurnStartKind: Equatable, Sendable {
    case user
    case automatic
    case recovery

    /// Automatic work may neither leave Plan mode nor enter it.
    public func permitsMode(_ mode: ModeKind) -> Bool {
        switch self {
        case .user, .recovery:
            return true
        case .automatic:
            return mode != .plan
        }
    }
}

public enum TurnAdmissionRoute: Equatable, Sendable {
    case startOrSteer
    case startIfIdle
}

public func turnStartKind(for input: TurnInput, idleDefault: TurnStartKind) -> TurnStartKind {
    if case .userInput(let content, _) = input, !content.isEmpty {
        return .user
    }
    return idleDefault
}

/// Host shutdown admission. Delegated child input bypasses the drain.
///
/// `start_or_steer` lets a thread-spawn child finish parent work.
/// `start_if_idle` lets a one-shot review delegate do the same.
/// Automatic starts never qualify.
public func turnInputRejectedForDraining(
    admitsTurnStart: Bool,
    route: TurnAdmissionRoute,
    kind: TurnStartKind,
    source: SessionSource,
    parentTurnId: String?
) -> Bool {
    if admitsTurnStart { return false }
    switch route {
    case .startOrSteer:
        if parentTurnId != nil, case .subAgent(.threadSpawn) = source {
            return false
        }
    case .startIfIdle:
        if kind == .user, parentTurnId != nil, case .subAgent(.review) = source {
            return false
        }
    }
    return true
}

public func validateStartOrSteerInput(_ input: TurnInput) throws {
    switch input {
    case .userInput:
        return
    case .responseItem(let item):
        if case .functionCallOutput(_, let callId, _, _, _, _) = item, callId == nil {
            return
        }
    case .interAgentCommunication:
        break
    }
    throw CodexErr.invalidRequest(
        "only user input or standalone function-call outputs can start or steer a turn"
    )
}

public func validateSteerOnlyInput(_ input: TurnInput) throws {
    guard case .userInput = input else {
        throw CodexErr.invalidRequest("only user input can steer a turn")
    }
}

/// User starts queue explicit input. `start_if_idle` also queues an empty
/// user message. Automatic and recovery starts queue every non-user item
/// and skip empty user input, which only resumes sampling.
public func shouldEnqueueSubmittedInput(
    _ input: TurnInput,
    kind: TurnStartKind,
    route: TurnAdmissionRoute
) -> Bool {
    switch kind {
    case .user:
        switch route {
        case .startOrSteer:
            return hasExplicitStartOrSteerInput(input)
        case .startIfIdle:
            return true
        }
    case .automatic, .recovery:
        if case .userInput = input {
            return false
        }
        return true
    }
}

/// Changed additional-context entries become response items, in key order.
/// The stored map is replaced by `incoming`, matching rust `BTreeMap` merge.
public func additionalContextItems(
    merging incoming: [String: AdditionalContextEntry],
    into stored: inout [String: AdditionalContextEntry]
) -> [TurnInput] {
    var items: [TurnInput] = []
    for key in incoming.keys.sorted() {
        guard let entry = incoming[key], stored[key] != entry else { continue }
        let fragment: ResponseItem
        switch entry.kind {
        case .untrusted:
            fragment = AdditionalContextUserFragment(key: key, value: entry.value).asResponseItem()
        case .application:
            fragment = AdditionalContextDeveloperFragment(key: key, value: entry.value).asResponseItem()
        }
        items.append(.responseItem(fragment))
    }
    stored = incoming
    return items
}

private func hasExplicitStartOrSteerInput(_ input: TurnInput) -> Bool {
    switch input {
    case .userInput(let content, _):
        return !content.isEmpty
    case .responseItem(let item):
        if case .functionCallOutput(_, let callId, _, _, _, _) = item {
            return callId == nil
        }
        return false
    case .interAgentCommunication:
        return false
    }
}
