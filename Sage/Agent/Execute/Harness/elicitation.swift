//
//  elicitation.swift
//  CodexCore
//
//  Port of codex-rs/core/src/elicitation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Coordinates user elicitations that pause tool-result delivery for a
//  session. `tokio::sync::watch` is an `AsyncStream<Bool>` plus waiter
//  continuations. `Mutex<State>` is `OSAllocatedUnfairLock`. Registration
//  `Drop` is `deinit`.
//

import Foundation
import os

/// Coordinates user elicitations that pause tool-result delivery for a session.
///
/// Registrations are counted so concurrent elicitations keep the session paused until all of them
/// finish. Consumers can subscribe to pause timeout progress or wait before returning an already
/// captured result.
public final class ElicitationService: @unchecked Sendable {
    private struct State {
        var outstanding: Int64 = 0
        var subscribers: [UUID: AsyncStream<Bool>.Continuation] = [:]
        var clearWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func register() -> ElicitationRegistration {
        increment()
        return ElicitationRegistration(service: self)
    }

    public func subscribe() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { state in
                continuation.yield(state.outstanding > 0)
                state.subscribers[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { state in
                    state.subscribers[id] = nil
                }
            }
        }
    }

    public func waitUntilClear() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock { state in
                if state.outstanding == 0 {
                    continuation.resume()
                } else {
                    state.clearWaiters.append(continuation)
                }
            }
        }
    }

    fileprivate func increment() {
        lock.withLock { state in
            let wasClear = state.outstanding == 0
            precondition(
                state.outstanding != Int64.max,
                "outstanding elicitation count overflowed"
            )
            state.outstanding += 1
            if wasClear {
                for subscriber in state.subscribers.values {
                    subscriber.yield(true)
                }
            }
        }
    }

    fileprivate func decrement() {
        var waiters: [CheckedContinuation<Void, Never>] = []
        lock.withLock { state in
            precondition(
                state.outstanding > 0,
                "elicitation registration count underflowed"
            )
            state.outstanding -= 1
            if state.outstanding == 0 {
                for subscriber in state.subscribers.values {
                    subscriber.yield(false)
                }
                waiters = state.clearWaiters
                state.clearWaiters.removeAll()
            }
        }
        for waiter in waiters {
            waiter.resume()
        }
    }
}

public final class ElicitationRegistration: @unchecked Sendable {
    private var service: ElicitationService?

    fileprivate init(service: ElicitationService) {
        self.service = service
    }

    deinit {
        service?.decrement()
    }
}
