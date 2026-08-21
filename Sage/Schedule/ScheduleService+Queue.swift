//
//  ScheduleService+Queue.swift
//  Sage
//

import Foundation

extension ScheduleService {
    // MARK: - Queue

    func enqueue(
        _ id: UUID,
        kind: ScheduleKind? = nil,
        afterWake: Bool = false,
        isTrial: Bool = false
    ) {
        let resolved = kind ?? records.first { $0.id == id }?.kind ?? .agent
        queue.enqueue(id, kind: resolved, afterWake: afterWake, isTrial: isTrial)
        publishQueue()
        kick()
    }

    func kick() {
        let jobs = queue.pumpStartable()
        guard !jobs.isEmpty else { return }
        publishQueue()
        for job in jobs {
            processOwners[job.id] = job.processOwnerID
            runTasks[job.id] = Task { [weak self] in
                await self?.performQueuedJob(job)
            }
        }
    }

    func performQueuedJob(_ job: ScheduleJobToken) async {
        let start = await run(job)
        queue.finishCurrent(job.id)
        processOwners[job.id] = nil
        runTasks[job.id] = nil
        publishQueue()
        switch start {
        case .unavailable:
            enqueueOverdue(excluding: job.id)

        case .skipped, .performed:
            enqueueOverdue()
        }
        kick()
    }

    enum ScheduledRunStart {
        case performed
        case skipped
        case unavailable
    }

    func run(_ job: ScheduleJobToken) async -> ScheduledRunStart {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Running scheduled job"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        guard var record = try? await taskRepository.loadSchedule(id: job.id) else {
            return .unavailable
        }
        let snapshotUpdatedAt = record.updatedAt
        let started = Date.now
        guard record.allowsRunnerStart else { return .skipped }

        let beat: ScheduleBeatResult
        var scriptOutcome: ScheduleScriptOutcome?
        switch record.kind {
        case .script:
            let outcome = await runner.runScript(record, processOwnerID: job.processOwnerID)
            if Task.isCancelled {
                beat = .stopped
            } else {
                beat = .script(outcome)
                scriptOutcome = outcome
            }

        case .agent:
            let outcome = await runner.runAgent(record)
            beat = Task.isCancelled ? .stopped : .agent(outcome)
        }

        let body = record.applyRun(
            beat,
            started: started,
            afterWake: job.afterWake,
            isTrial: job.isTrial
        )
        let persisted = await commitAfterRun(
            record,
            snapshotUpdatedAt: snapshotUpdatedAt,
            scriptRun: scriptRunRecord(for: record, outcome: scriptOutcome, started: started)
        )
        guard persisted else { return .performed }
        postRunNotification(
            for: record,
            body: body,
            taskID: record.lastRunTaskID,
            notify: beat.notification(isTrial: job.isTrial, cadence: record.cadence)
        )
        return .performed
    }

    func postRunNotification(
        for record: ScheduleRecord,
        body: String,
        taskID: UUID?,
        notify: ScheduleNotify
    ) {
        let playsSound: Bool
        switch notify {
        case .mute:
            return

        case .silent:
            playsSound = false

        case .sound:
            playsSound = true
        }
        ScheduleNotifier.post(
            ScheduleNotificationPayload(
                scheduleID: record.id,
                title: record.title,
                body: body,
                kind: record.kind,
                projectID: record.projectID,
                taskID: taskID
            ),
            playsSound: playsSound
        )
    }

    /// Persists run results. Deleted rows are left alone; Pause / Re-plan during the run is kept.
    @discardableResult
    func commitAfterRun(
        _ result: ScheduleRecord,
        snapshotUpdatedAt: Date,
        scriptRun: ScheduleRunRecord? = nil
    ) async -> Bool {
        guard let live = try? await taskRepository.loadSchedule(id: result.id) else {
            forget(result.id)
            return false
        }
        do {
            if live.updatedAt > snapshotUpdatedAt {
                return try await persist(live.adoptingRunMetadata(from: result), scriptRun: scriptRun)
            }
            return try await persist(result, scriptRun: scriptRun)
        } catch {
            lastError = "Couldn’t update that schedule."
            return false
        }
    }

    func scriptRunRecord(
        for record: ScheduleRecord,
        outcome: ScheduleScriptOutcome?,
        started: Date
    ) -> ScheduleRunRecord? {
        guard record.kind == .script else { return nil }
        return ScheduleRunRecord(
            id: UUID(),
            scheduleID: record.id,
            startedAt: started,
            endedAt: .now,
            exitCode: outcome?.exitCode,
            outputExcerpt: record.lastStatus
        )
    }

    /// Returns `false` when the row was deleted while this write was in flight.
    @discardableResult
    func persist(_ record: ScheduleRecord, scriptRun: ScheduleRunRecord? = nil) async throws -> Bool {
        if deletedIDs.contains(record.id) {
            forget(record.id)
            return false
        }
        try await taskRepository.upsertSchedule(record, scriptRun: scriptRun)
        if deletedIDs.contains(record.id) {
            try? await taskRepository.deleteSchedule(id: record.id)
            forget(record.id)
            return false
        }
        remember(record)
        return true
    }

    func remember(_ record: ScheduleRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        records = ScheduleRecord.sortedForListing(records)
        trigger.arm(records: records)
        if !runningIDs.contains(record.id) {
            enqueueOverdue()
        }
    }

    func forget(_ id: UUID) {
        records.removeAll { $0.id == id }
        queue.forget(id)
        publishQueue()
        trigger.arm(records: records)
    }

    func publishQueue() {
        queuedIDs = queue.queuedIDs
        runningIDs = queue.runningIDs
    }

    /// Enqueues enabled recipes whose `nextFireAt` is already due (e.g. after a trial).
    func enqueueOverdue(now: Date = .now, excluding excludedID: UUID? = nil) {
        for record in records where record.isDue(at: now) {
            if record.id == excludedID { continue }
            guard !queue.contains(record.id) else { continue }
            enqueue(record.id, kind: record.kind)
        }
    }

    func reloadAndArmTimer() async {
        await reload()
        await scanDue()
    }
}
