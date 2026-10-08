//
//  inject.swift
//  Sage
//
//  Port of codex-rs/core/src/session/inject.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Active-turn inject goes onto rust `pending_input` and accepts mailbox
//  delivery. `injectHookContextIfRunning` requires a live task. Items that
//  miss the turn fall back to history via `injectNoNewTurn`.
//

import CodexProtocol
import Foundation

extension Session {
    func inject(_ item: ResponseItem) {
        state.recordItems([item])
    }

    /// rust `inject_if_running`. Returns the items when no turn is active.
    @discardableResult
    func injectIfRunning(_ items: [ResponseItem]) -> [ResponseItem]? {
        guard let active = activeTurn else { return items }
        inputQueue.extendPendingInputAndAcceptMailboxDeliveryForTurnState(
            active.turnState,
            input: items.map { .responseItem($0) }
        )
        return nil
    }

    /// rust `inject_hook_context_if_running`.
    @discardableResult
    func injectHookContextIfRunning(_ items: [ResponseItem]) -> [ResponseItem]? {
        guard let active = activeTurn, active.task != nil else { return items }
        inputQueue.extendPendingInputAndAcceptMailboxDeliveryForTurnState(
            active.turnState,
            input: items.map { .responseItem($0) }
        )
        return nil
    }

    /// rust `inject_no_new_turn`.
    func injectNoNewTurn(_ items: [ResponseItem], currentTurnContext: TurnContext? = nil) {
        if injectIfRunning(items) == nil { return }
        let turn = currentTurnContext ?? newTurnContext()
        recordConversationItems(turn, items: items)
    }
}
