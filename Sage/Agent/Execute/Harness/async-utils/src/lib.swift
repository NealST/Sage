//
//  lib.swift
//  CodexAsyncUtils
//
//  Port of codex-rs/async-utils/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `tokio_util::sync::CancellationToken` maps to the Sage addition in
//  cancellation_token.swift. `OrCancelExt::or_cancel` maps to the free
//  function `orCancel(_:_:)` (Swift cannot extend "any async operation");
//  `tokio::select!` maps to a race between two unstructured tasks where the
//  first completion wins.
//
//  Unlike `tokio::select!`, which drops the losing future, a losing
//  operation `Task` that does not observe cancellation keeps running in the
//  background; its result is discarded. This preserves the observable
//  `or_cancel` contract (the winner's result is returned promptly) but not
//  the loser's side-effect timing.
//

import Foundation

/// Stack budget for threads that poll Codex async work
/// (`THREAD_STACK_SIZE_BYTES`).
public let threadStackSizeBytes = 16 * 1024 * 1024

/// `CancelErr`.
public enum CancelErr: Error, Equatable {
    case cancelled
}

private enum OrCancelRace<T> {
    case completed(T)
    case cancelled

    var result: Result<T, CancelErr> {
        switch self {
        case .completed(let value):
            return .success(value)
        case .cancelled:
            return .failure(.cancelled)
        }
    }
}

/// First completion wins; resumes the continuation exactly once and cancels
/// both racing tasks (cooperative) afterwards.
private final class OrCancelBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var tasks: [Task<Void, Never>] = []

    func register(_ task: Task<Void, Never>) {
        lock.withLock { tasks.append(task) }
    }

    func finish(
        _ race: OrCancelRace<T>,
        continuation: CheckedContinuation<Result<T, CancelErr>, Never>
    ) {
        let pending = lock.withLock { () -> [Task<Void, Never>]? in
            if resumed { return nil }
            resumed = true
            return tasks
        }
        guard let pending else { return }
        for task in pending {
            task.cancel()
        }
        continuation.resume(returning: race.result)
    }
}

/// `OrCancelExt::or_cancel` — races `operation` against token cancellation.
///
/// Returns `.failure(.cancelled)` if the token fires first (or is already
/// cancelled), `.success` with the operation's result otherwise.
public func orCancel<T: Sendable>(
    _ token: CancellationToken,
    _ operation: @escaping @Sendable () async -> T
) async -> Result<T, CancelErr> {
    await withCheckedContinuation { continuation in
        let box = OrCancelBox<T>()
        let operationTask = Task {
            box.finish(.completed(await operation()), continuation: continuation)
        }
        let watcherTask = Task {
            await token.waitForCancellation()
            box.finish(.cancelled, continuation: continuation)
        }
        box.register(operationTask)
        box.register(watcherTask)
    }
}
