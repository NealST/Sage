//
//  input_queue.swift
//  Sage
//
//  Port of codex-rs/core/src/session/input_queue.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Mailbox gauges and residency guards are omitted. The queue still
//  preserves user / tool-output / inter-agent ordering, and notifies
//  mailbox vs steer waiters the way rust `watch` does.
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

enum InputQueueActivity: Equatable, Sendable {
    case mailbox
    case steer
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

    func takeAll() -> [SessionTurnInput] {
        let items = self.items
        self.items.removeAll()
        return items
    }

    var isEmpty: Bool { items.isEmpty }

    func hasPendingSteer() -> Bool {
        items.contains { $0.isSteerInput }
    }
}

private struct PendingMailboxCommunication {
    var communication: InterAgentCommunication
    var startOptions: TurnStartOptions
}

final class InputQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [SessionTurnInput] = []
    private var mailboxMails: [PendingMailboxCommunication] = []
    private var activityWaiters: [UUID: AsyncStream<InputQueueActivity>.Continuation] = [:]

    init() {}

    func enqueue(_ item: SessionTurnInput) {
        lock.lock()
        pending.append(item)
        lock.unlock()
        if item.isSteerInput {
            notifyActivity(.steer)
        }
    }

    func hasSessionPendingItems() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pending.isEmpty
    }

    func takeAll() -> [SessionTurnInput] {
        lock.lock()
        let items = pending
        pending.removeAll()
        lock.unlock()
        return items
    }

    func subscribeActivity(
        turnState: TurnState? = nil,
        hasPendingSteer: Bool = false
    ) -> (AsyncStream<InputQueueActivity>, InputQueueActivity?) {
        let stream = subscribeActivityStream()
        let pendingActivity: InputQueueActivity?
        if hasPendingSteer || turnState?.pendingInput.hasPendingSteer() == true || sessionPendingSteer() {
            pendingActivity = .steer
        } else if hasPendingMailboxItems() {
            pendingActivity = .mailbox
        } else {
            pendingActivity = nil
        }
        return (stream, pendingActivity)
    }

    func subscribeActivityStream() -> AsyncStream<InputQueueActivity> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            activityWaiters[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.activityWaiters.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func enqueueMailboxCommunication(
        _ communication: InterAgentCommunication,
        startOptions: TurnStartOptions = TurnStartOptions()
    ) {
        lock.lock()
        mailboxMails.append(
            PendingMailboxCommunication(communication: communication, startOptions: startOptions)
        )
        lock.unlock()
        notifyActivity(.mailbox)
    }

    func hasPendingMailboxItems() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !mailboxMails.isEmpty
    }

    func hasTriggerTurnMailboxItems() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return mailboxMails.contains { $0.communication.triggerTurn }
    }

    func drainMailboxInputItems() -> ([SessionTurnInput], TurnStartOptions) {
        lock.lock()
        let pendingMails = mailboxMails
        mailboxMails.removeAll()
        lock.unlock()
        var startOptions = pendingMails.reversed()
            .first(where: { $0.communication.triggerTurn })?
            .startOptions ?? TurnStartOptions()
        startOptions.parentTurnId = reducedTriggerParentTurnId(pendingMails)
        startOptions.rootTurnId = firstTriggerRootTurnId(pendingMails)
        let items = pendingMails.map { SessionTurnInput.interAgentCommunication($0.communication) }
        return (items, startOptions)
    }

    func turnStateForSubId(_ activeTurn: ActiveTurn?, subId: String) -> TurnState? {
        guard let activeTurn, let task = activeTurn.task, task.turnContext.subId == subId else {
            return nil
        }
        return activeTurn.turnState
    }

    func clearPending(_ activeTurn: ActiveTurn) {
        activeTurn.turnState.clearPendingWaiters()
        activeTurn.turnState.pendingInput.items.removeAll()
    }

    func deferMailboxDeliveryToNextTurn(_ activeTurn: ActiveTurn?, subId: String) {
        guard let turnState = turnStateForSubId(activeTurn, subId: subId) else { return }
        let shouldDefer = !turnState.pendingInput.items.contains { input in
            switch input {
            case .interAgentCommunication(let communication) where !communication.triggerTurn:
                return false
            default:
                return true
            }
        }
        guard shouldDefer else { return }
        turnState.setMailboxDeliveryPhase(.nextTurn)
    }

    func acceptMailboxDeliveryForCurrentTurn(_ activeTurn: ActiveTurn?, subId: String) {
        guard let turnState = turnStateForSubId(activeTurn, subId: subId) else { return }
        acceptMailboxDeliveryForTurnState(turnState)
    }

    func acceptMailboxDeliveryForTurnState(_ turnState: TurnState) {
        turnState.acceptMailboxDeliveryForCurrentTurn()
    }

    func extendPendingInputAndAcceptMailboxDeliveryForTurnState(
        _ turnState: TurnState,
        input: [SessionTurnInput]
    ) {
        turnState.pendingInput.items.append(contentsOf: input)
        turnState.acceptMailboxDeliveryForCurrentTurn()
        notifyActivity(.steer)
    }

    func extendPendingInputForTurnState(_ turnState: TurnState, input: [SessionTurnInput]) {
        turnState.pendingInput.items.append(contentsOf: input)
    }

    func takePendingInputForTurnState(_ turnState: TurnState) -> [SessionTurnInput] {
        turnState.pendingInput.takeAll()
    }

    func getPendingInput(_ activeTurn: ActiveTurn?) -> [SessionTurnInput] {
        getPendingInputWithStartOptions(activeTurn).0
    }

    func getPendingInputWithStartOptions(
        _ activeTurn: ActiveTurn?
    ) -> ([SessionTurnInput], TurnStartOptions) {
        let (turnPending, acceptsMailboxDelivery): ([SessionTurnInput], Bool)
        if let activeTurn {
            let accepts = activeTurn.turnState.acceptsMailboxDeliveryForCurrentTurn()
            let pendingInput = accepts ? activeTurn.turnState.pendingInput.takeAll() : []
            (turnPending, acceptsMailboxDelivery) = (pendingInput, accepts)
        } else {
            (turnPending, acceptsMailboxDelivery) = ([], true)
        }
        if !acceptsMailboxDelivery {
            return ([], TurnStartOptions())
        }
        lock.lock()
        let sessionPending = pending
        pending.removeAll()
        lock.unlock()
        let (mailboxItems, startOptions) = drainMailboxInputItems()
        var items = sessionPending
        items.append(contentsOf: turnPending)
        items.append(contentsOf: mailboxItems)
        return (items, startOptions)
    }

    func hasPendingInput(_ activeTurn: ActiveTurn?) -> Bool {
        let (hasTurnPendingInput, acceptsMailboxDelivery): (Bool, Bool)
        if let activeTurn {
            (
                hasTurnPendingInput,
                acceptsMailboxDelivery
            ) = (
                !activeTurn.turnState.pendingInput.isEmpty,
                activeTurn.turnState.acceptsMailboxDeliveryForCurrentTurn()
            )
        } else {
            (hasTurnPendingInput, acceptsMailboxDelivery) = (false, true)
        }
        if !acceptsMailboxDelivery {
            return false
        }
        if hasTurnPendingInput {
            return true
        }
        lock.lock()
        let hasSessionPending = !pending.isEmpty
        lock.unlock()
        if hasSessionPending {
            return true
        }
        return hasPendingMailboxItems()
    }

    func hasPendingSteer(_ turnState: TurnState? = nil) -> Bool {
        if turnState?.pendingInput.hasPendingSteer() == true {
            return true
        }
        return sessionPendingSteer()
    }

    func waitForActivity(
        turnState: TurnState? = nil,
        hasPendingSteer: Bool = false,
        timeout: Duration
    ) async -> InputQueueActivity? {
        let (stream, pendingActivity) = subscribeActivity(
            turnState: turnState,
            hasPendingSteer: hasPendingSteer
        )
        if let pendingActivity {
            return pendingActivity
        }
        return await withTaskGroup(of: InputQueueActivity?.self) { group in
            group.addTask {
                for await activity in stream {
                    return activity
                }
                return nil
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return nil
                } catch {
                    return nil
                }
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            while await group.next() != nil {}
            return first
        }
    }

    private func sessionPendingSteer() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending.contains { $0.isSteerInput }
    }

    private func notifyActivity(_ activity: InputQueueActivity) {
        lock.lock()
        let waiters = Array(activityWaiters.values)
        lock.unlock()
        for waiter in waiters {
            waiter.yield(activity)
        }
    }
}

extension SessionTurnInput {
    var isSteerInput: Bool {
        switch self {
        case .userInput, .functionCallOutput:
            return true
        case .responseItem, .interAgentCommunication:
            return false
        }
    }
}

private func nonemptyTurnId(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    return value
}

private func reducedTriggerParentTurnId(_ mails: [PendingMailboxCommunication]) -> String? {
    let ids = mails.filter { $0.communication.triggerTurn }.map(\.startOptions.parentTurnId)
    guard let first = ids.first else { return nil }
    var expected = first
    for candidate in ids.dropFirst() {
        expected = expected.flatMap { id in candidate == id ? id : nil }
    }
    return nonemptyTurnId(expected)
}

private func firstTriggerRootTurnId(_ mails: [PendingMailboxCommunication]) -> String? {
    guard let mail = mails.first(where: { $0.communication.triggerTurn }) else { return nil }
    guard nonemptyTurnId(mail.startOptions.parentTurnId) != nil else { return nil }
    return nonemptyTurnId(mail.startOptions.rootTurnId)
}
