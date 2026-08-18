//
//  SessionOperationGate.swift
//  Sage
//

import Foundation

/// Busy lock + cancellable in-flight work for one agent window.
@MainActor
final class SessionOperationGate {
    private let state: AgentSessionState
    private let processOwnerID: UUID
    private var workTask: Task<Void, Never>?
    /// Balanced App Nap / automatic-termination token for user-initiated work.
    private var activityToken: NSObjectProtocol?

    init(state: AgentSessionState, processOwnerID: UUID = UUID()) {
        self.state = state
        self.processOwnerID = processOwnerID
    }

    @discardableResult
    func begin() -> Bool {
        guard !state.isTornDown, !state.isBusy else { return false }
        state.setBusy(true)
        beginActivity()
        return true
    }

    func end() {
        state.setBusy(false)
        endActivity()
    }

    /// Cancels the current work task and waits for it to finish.
    func cancelInFlight() async {
        workTask?.cancel()
        if let work = workTask {
            await work.value
        }
        workTask = nil
        state.setBusy(false)
        endActivity()
    }

    /// Soft-stop: terminate this session’s child processes and cancel the in-flight task.
    func requestStop() {
        ProcessRunner.terminateProcesses(ownedBy: processOwnerID)
        workTask?.cancel()
    }

    /// Runs `body` under the busy lock with a cancellable `workTask`.
    @discardableResult
    func run(_ body: @escaping @MainActor () async -> Void) async -> Bool {
        guard begin() else { return false }
        defer { end(); workTask = nil }

        let owner: UUID? = processOwnerID
        let work = Task { @MainActor in
            await ProcessRunner.$ownerID.withValue(owner) {
                await body()
            }
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
        let owner: UUID? = processOwnerID
        let work = Task { @MainActor in
            await ProcessRunner.$ownerID.withValue(owner) {
                result = await body()
            }
        }
        workTask = work
        await work.value
        return result
    }

    // MARK: - App Nap

    private func beginActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Sage agent turn"
        )
    }

    private func endActivity() {
        guard let token = activityToken else { return }
        activityToken = nil
        ProcessInfo.processInfo.endActivity(token)
    }
}
