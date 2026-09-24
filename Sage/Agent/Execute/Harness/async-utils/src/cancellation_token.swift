//
//  cancellation_token.swift
//  CodexAsyncUtils
//
//  Sage addition (no codex counterpart).
//
//  Stands in for `tokio_util::sync::CancellationToken`: a thread-safe token
//  that wakes all waiters when cancelled. `token.cancelled().await` maps to
//  `await token.waitForCancellation()`.
//
//  Cloning a `CancellationToken` in Rust shares the underlying state; the
//  Swift port is a reference type for the same reason — every copy shares
//  cancellation state, like Rust's `Clone`.
//
//  Unlike tokio, `waitForCancellation()` also returns when the awaiting
//  Swift `Task` is cancelled, so racing a watcher task does not leak it.
//

import Foundation

/// `tokio_util::sync::CancellationToken`.
public final class CancellationToken: @unchecked Sendable {

    /// One suspended `waitForCancellation()` call.
    private final class Waiter: @unchecked Sendable {
        let lock = NSLock()
        var continuation: CheckedContinuation<Void, Never>?
        /// Fired by `cancel()`/task-cancellation before or after the
        /// continuation is stored; exactly-once resume.
        var fired = false

        /// Marks fired and returns the continuation to resume, if any.
        func fire() -> CheckedContinuation<Void, Never>? {
            lock.withLock {
                if fired { return nil }
                fired = true
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }
        }

        /// Stores the continuation, or returns it for immediate resume when
        /// the waiter already fired.
        func setContinuation(
            _ continuation: CheckedContinuation<Void, Never>
        ) -> CheckedContinuation<Void, Never>? {
            lock.withLock {
                if fired { return continuation }
                self.continuation = continuation
                return nil
            }
        }
    }

    private struct State {
        var isCancelled = false
        var waiters: [UUID: Waiter] = [:]
    }

    /// `NSLock` + `withLock` stands in for a mutex-protected state.
    private let state = NSLock()
    private var protectedState = State()

    private func withState<R>(_ body: (inout State) -> R) -> R {
        state.withLock { body(&protectedState) }
    }

    public init() {}

    /// `CancellationToken::cancel` — wakes every current and future waiter.
    public func cancel() {
        let waiters = withState { state -> [Waiter] in
            state.isCancelled = true
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.fire()?.resume()
        }
    }

    /// `CancellationToken::is_cancelled`.
    public var isCancelled: Bool {
        withState { $0.isCancelled }
    }

    /// `token.cancelled().await` — completes immediately if already
    /// cancelled, and also completes if the awaiting task is cancelled.
    public func waitForCancellation() async {
        let id = UUID()
        let waiter = Waiter()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let immediate = withState { state -> Bool in
                    if state.isCancelled { return true }
                    state.waiters[id] = waiter
                    return false
                }
                if immediate {
                    continuation.resume()
                    return
                }
                // `cancel()` may have fired between registration and here.
                waiter.setContinuation(continuation)?.resume()
            }
        } onCancel: {
            let removed = withState { $0.waiters.removeValue(forKey: id) }
            (removed ?? waiter).fire()?.resume()
        }
    }
}
