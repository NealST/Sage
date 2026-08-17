//
//  ScheduleJobQueue.swift
//  Sage
//
//  In-process FIFO of due schedules. Scripts may overlap; agents are serial.
//  Pause/Delete dequeue; an in-flight run is left alone until Stop or finish.
//

import Foundation

/// Token for a job that has left the pending queue and may start executing.
nonisolated struct ScheduleJobToken: Equatable, Sendable {
    let id: UUID
    let kind: ScheduleKind
    let afterWake: Bool
    let isTrial: Bool
    /// Isolates this script beat’s ProcessRunner from other jobs and window Stop.
    let processOwnerID: UUID
}

/// Pending / queued / running sets for the schedule runner.
@MainActor
final class ScheduleJobQueue {
    /// Maximum overlapping script beats. Agents are always serial.
    static let maxConcurrentScripts = 4

    private(set) var queuedIDs: Set<UUID> = []
    private(set) var runningIDs: Set<UUID> = []

    private var pendingIDs: [UUID] = []
    private var afterWakeIDs: Set<UUID> = []
    private var trialIDs: Set<UUID> = []
    private var kinds: [UUID: ScheduleKind] = [:]
    private var runningAgentIDs: Set<UUID> = []

    /// Whether this id is already queued or running.
    func contains(_ id: UUID) -> Bool {
        runningIDs.contains(id) || queuedIDs.contains(id)
    }

    var hasPending: Bool { !pendingIDs.isEmpty }

    /// Enqueues `id`. Returns `false` if it was already queued or running.
    @discardableResult
    func enqueue(
        _ id: UUID,
        kind: ScheduleKind,
        afterWake: Bool = false,
        isTrial: Bool = false
    ) -> Bool {
        guard !contains(id) else { return false }
        kinds[id] = kind
        queuedIDs.insert(id)
        pendingIDs.append(id)
        if afterWake { afterWakeIDs.insert(id) }
        if isTrial { trialIDs.insert(id) }
        return true
    }

    /// Drops a job from the pending queue. Does not cancel an in-flight run.
    func dequeue(_ id: UUID) {
        pendingIDs.removeAll { $0 == id }
        queuedIDs.remove(id)
        afterWakeIDs.remove(id)
        trialIDs.remove(id)
        if !runningIDs.contains(id) {
            kinds.removeValue(forKey: id)
        }
    }

    /// Removes the id from pending, queued, and running.
    func forget(_ id: UUID) {
        dequeue(id)
        runningIDs.remove(id)
        runningAgentIDs.remove(id)
        kinds.removeValue(forKey: id)
    }

    /// Starts every pending job that is allowed to overlap with current runs.
    func pumpStartable() -> [ScheduleJobToken] {
        var started: [ScheduleJobToken] = []
        var keep: [UUID] = []
        var runningScripts = runningIDs.subtracting(runningAgentIDs).count
        var agentBusy = !runningAgentIDs.isEmpty

        for id in pendingIDs {
            let kind = kinds[id] ?? .agent
            if kind == .agent && agentBusy {
                keep.append(id)
                continue
            }
            if kind == .script && runningScripts >= Self.maxConcurrentScripts {
                keep.append(id)
                continue
            }
            queuedIDs.remove(id)
            runningIDs.insert(id)
            if kind == .agent {
                runningAgentIDs.insert(id)
                agentBusy = true
            } else {
                runningScripts += 1
            }
            started.append(
                ScheduleJobToken(
                    id: id,
                    kind: kind,
                    afterWake: afterWakeIDs.remove(id) != nil,
                    isTrial: trialIDs.remove(id) != nil,
                    processOwnerID: UUID()
                )
            )
        }
        pendingIDs = keep
        return started
    }

    func finishCurrent(_ id: UUID) {
        runningIDs.remove(id)
        runningAgentIDs.remove(id)
        kinds.removeValue(forKey: id)
    }
}
