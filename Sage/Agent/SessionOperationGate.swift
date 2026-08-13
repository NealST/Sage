//
//  SessionOperationGate.swift
//  Sage
//

import Foundation

/// Busy lock + cancellable in-flight work for one agent window.
@MainActor
final class SessionOperationGate {
    private let state: AgentSessionState
    private var workTask: Task<Void, Never>?

    init(state: AgentSessionState) {
        self.state = state
    }

    @discardableResult
    func begin() -> Bool {
        guard !state.isTornDown, !state.isBusy else { return false }
        state.isBusy = true
        return true
    }

    func end() {
        state.isBusy = false
    }

    /// Cancels the current work task and waits for it to finish.
    func cancelInFlight() async {
        workTask?.cancel()
        if let work = workTask {
            await work.value
        }
        workTask = nil
        state.isBusy = false
    }

    /// Soft-stop: terminate child processes and cancel the in-flight task.
    func requestStop() {
        ProcessRunner.terminateAll()
        workTask?.cancel()
    }

    /// Runs `body` under the busy lock with a cancellable `workTask`.
    @discardableResult
    func run(_ body: @escaping @MainActor () async -> Void) async -> Bool {
        guard begin() else { return false }
        defer { end(); workTask = nil }

        let work = Task { @MainActor in
            await body()
        }
        workTask = work
        await work.value
        return true
    }

    /// Like `run`, but returns a Bool produced by `body` (e.g. submit accepted).
    func runAccepted(_ body: @escaping @MainActor () async -> Bool) async -> Bool {
        guard begin() else { return false }
        defer { end(); workTask = nil }

        var result = false
        let work = Task { @MainActor in
            result = await body()
        }
        workTask = work
        await work.value
        return result
    }
}
