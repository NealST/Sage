//
//  input_queue.swift
//  Sage
//
//  Port of codex-rs/core/src/session/input_queue.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Mailbox gauges and residency guards are omitted. The queue still
//  preserves user / tool-output / inter-agent ordering.
//

import CodexProtocol
import Foundation

struct UserInputMetadata: Equatable, Sendable {
    var acceptanceOrder: UInt64?
    var origin: String

    init(acceptanceOrder: UInt64? = nil, origin: String = "user") {
        self.acceptanceOrder = acceptanceOrder
        self.origin = origin
    }
}

enum SessionTurnInput: Equatable, Sendable {
    case userInput(content: [UserInput], clientId: String?, metadata: UserInputMetadata)
    case functionCallOutput(ResponseItem)
    case responseItem(ResponseItem)
    case interAgentCommunication(InterAgentCommunication)
}

final class SessionTurnInputQueue: @unchecked Sendable {
    var items: [SessionTurnInput] = []

    init() {}

    func enqueue(_ item: SessionTurnInput) {
        items.append(item)
    }

    func dequeue() -> SessionTurnInput? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    var isEmpty: Bool { items.isEmpty }
}

final class InputQueue: @unchecked Sendable {
    var pending: [SessionTurnInput] = []

    init() {}

    func enqueue(_ item: SessionTurnInput) {
        pending.append(item)
    }

    func takeAll() -> [SessionTurnInput] {
        let items = pending
        pending.removeAll()
        return items
    }

    func hasTriggerTurnMailboxItems() async -> Bool {
        !pending.isEmpty
    }
}
