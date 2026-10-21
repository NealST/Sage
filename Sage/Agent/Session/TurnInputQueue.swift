//
//  TurnInputQueue.swift
//  Sage
//

import Foundation

nonisolated struct QueuedUserTurn: Equatable, Sendable {
    var text: String
    var attachments: [MessageAttachment]
}

@MainActor
@Observable
final class TurnInputQueue {
    var offer: QueuedUserTurn? {
        didSet { notifyChanged() }
    }
    var items: [QueuedUserTurn] = [] {
        didSet { notifyChanged() }
    }
    var pendingSteer: QueuedUserTurn? {
        didSet { notifyChanged() }
    }
    /// Owner hook — every queue mutation (including park/restore) funnels here
    /// so queued turns persist alongside the composer draft.
    @ObservationIgnored var onChanged: (() -> Void)?

    var hasOffer: Bool { offer != nil }
    var hasQueuedItems: Bool { !items.isEmpty }

    func enqueueOffer() {
        guard let offer else { return }
        items.append(offer)
        self.offer = nil
    }

    func popNext() -> QueuedUserTurn? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    struct Snapshot: Equatable {
        var offer: QueuedUserTurn?
        var items: [QueuedUserTurn]
        var pendingSteer: QueuedUserTurn?

        var isEmpty: Bool {
            offer == nil && items.isEmpty && pendingSteer == nil
        }
    }

    var snapshot: Snapshot {
        Snapshot(offer: offer, items: items, pendingSteer: pendingSteer)
    }

    func apply(_ snapshot: Snapshot) {
        offer = snapshot.offer
        items = snapshot.items
        pendingSteer = snapshot.pendingSteer
    }

    func reset() {
        offer = nil
        items = []
        pendingSteer = nil
    }

    private func notifyChanged() {
        onChanged?()
    }
}
