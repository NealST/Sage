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
    var offer: QueuedUserTurn?
    var items: [QueuedUserTurn] = []
    var pendingSteer: QueuedUserTurn?

    var hasOffer: Bool { offer != nil }

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
}
