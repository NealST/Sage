//
//  ScheduleService.swift
//  Sage
//
//  Facade: persist recipes, arm the wall-clock trigger, drain the job queue.
//

import Foundation

@MainActor
@Observable
final class ScheduleService {
    private(set) var records: [ScheduleRecord] = []
    /// Jobs waiting in the in-process queue (not yet executing).
    private(set) var queuedIDs: Set<UUID> = []
    /// Jobs currently executing.
    private(set) var runningIDs: Set<UUID> = []
    /// Last user-facing save / pause / delete / re-plan failure, if any.
    private(set) var lastError: String?

    var runningTitle: String? {
        records.first { runningIDs.contains($0.id) }?.title
            ?? records.first { queuedIDs.contains($0.id) }?.title
    }

    private let taskRepository: any TaskRepository
    private let queue = ScheduleJobQueue()
    private let trigger: ScheduleTrigger
    private let runner: ScheduleRunner
    /// IDs deleted this session; blocks in-flight upserts from recreating a row.
    private var deletedIDs: Set<UUID> = []
    /// Unstructured beat tasks so Stop can cancel one job without draining others.
    private var runTasks: [UUID: Task<Void, Never>] = [:]
    private var processOwners: [UUID: UUID] = [:]

    init(
        taskRepository: any TaskRepository,
        settings: ModelSettings,
        mcpHub: CapabilityStore,
        skillStateStore: SkillStateStore
    ) {
        self.taskRepository = taskRepository
        self.runner = ScheduleRunner(
            taskRepository: taskRepository,
            settings: settings,
            mcpHub: mcpHub,
            skillStateStore: skillStateStore
        )
        self.trigger = ScheduleTrigger()
        self.trigger.onFire = { [weak self] in
            await self?.scanDue()
        }
    }

    /// Starts the in-process timer and wake-from-sleep scan. Safe to call once.
    func start() async {
        trigger.startWakeObserver()
        await reloadAndArmTimer()
    }

    func reload() async {
        do {
            records = try await taskRepository.listSchedules()
            trigger.arm(records: records)
            enqueueOverdue()
        } catch {
            lastError = "Couldn’t load schedules."
        }
    }

    /// Persists a recipe. When `runOnceNow` is true, also enqueues one trial run.
    @discardableResult
    func save(_ schedule: ScheduleRecord, runOnceNow: Bool = false) async -> Bool {
        do {
            var next = schedule
            next.cadence = next.cadence.resolvedForSave()
            next.updatedAt = .now
            if next.enabled, next.status != .paused, next.status != .awaitingConfirmation {
                next.nextFireAt = ScheduleClock.nextFireDate(for: next.cadence)
            }
            guard try await persist(next) else {
                lastError = "That schedule is gone."
                return false
            }
            lastError = nil
            ScheduleNotifier.requestAuthorization()
            if runOnceNow {
                enqueue(next.id, kind: next.kind, isTrial: true)
            }
            return true
        } catch {
            lastError = "Couldn’t save that schedule."
            return false
        }
    }

    /// Turns a schedule on (`true`) or off (`false`). Off is Pause; on is Resume.
    @discardableResult
    func setEnabled(_ id: UUID, enabled: Bool) async -> Bool {
        guard var record = records.first(where: { $0.id == id }) else {
            lastError = "That schedule is gone."
            return false
        }
        if enabled {
            record.enabled = true
            switch record.status {
            case .awaitingConfirmation:
                break

            case .paused, .failed:
                record.status = record.kind == .agent && record.frozenWorkPlan == nil
                    ? .needsFirstRun
                    : .armed
                record.nextFireAt = ScheduleClock.nextFireDate(for: record.cadence)

            default:
                if record.nextFireAt == nil || (record.nextFireAt.map { $0 <= Date.now } ?? false) {
                    record.nextFireAt = ScheduleClock.nextFireDate(for: record.cadence)
                }
            }
        } else {
            record.enabled = false
            if record.status != .awaitingConfirmation {
                record.status = .paused
            }
            queue.dequeue(id)
            publishQueue()
        }
        record.updatedAt = .now
        do {
            guard try await persist(record) else {
                lastError = "That schedule is gone."
                return false
            }
            lastError = nil
            return true
        } catch {
            if !enabled {
                enqueueOverdue()
            }
            lastError = enabled
                ? "Couldn’t resume that schedule."
                : "Couldn’t pause that schedule."
            return false
        }
    }

    @discardableResult
    func delete(_ id: UUID) async -> Bool {
        deletedIDs.insert(id)
        cancelRun(id)
        queue.dequeue(id)
        publishQueue()
        do {
            try await taskRepository.deleteSchedule(id: id)
            lastError = nil
            forget(id)
            return true
        } catch {
            deletedIDs.remove(id)
            enqueueOverdue()
            lastError = "Couldn’t delete that schedule."
            return false
        }
    }

    /// Clears the frozen recipe so the next fire runs the full first-run pipeline.
    @discardableResult
    func replan(_ id: UUID) async -> Bool {
        guard var record = records.first(where: { $0.id == id }) else {
            lastError = "That schedule is gone."
            return false
        }
        record.setFrozenWorkPlan(nil)
        record.status = .needsFirstRun
        record.enabled = true
        record.lastStatus = "Needs setup — next run will re-plan."
        record.updatedAt = .now
        record.nextFireAt = ScheduleClock.nextFireDate(for: record.cadence)
        do {
            guard try await persist(record) else {
                lastError = "That schedule is gone."
                return false
            }
            lastError = nil
            return true
        } catch {
            lastError = "Couldn’t re-plan that schedule."
            return false
        }
    }

    /// Hides the Dashboard error banner.
    func clearLastError() {
        lastError = nil
    }

    /// Stops this beat only. Pause still controls future fires.
    func cancelRun(_ id: UUID) {
        runTasks[id]?.cancel()
        if let owner = processOwners[id] {
            ProcessRunner.terminateProcesses(ownedBy: owner)
        }
        runner.stopAgent(forScheduleID: id)
    }

    /// Cancels in-flight beats and the wall timer so Quit does not leave half-written runs.
    func prepareForQuit() async {
        trigger.disarm()
        let ids = Array(runTasks.keys)
        for id in ids {
            cancelRun(id)
        }
        let tasks = Array(runTasks.values)
        for task in tasks {
            await task.value
        }
    }

    /// First-run `act` confirmation finished on a window session (not the ephemeral runner).
    func noteSpawnedTaskSettled(
        taskID: UUID,
        plan: WorkPlan?,
        outcome: AgentTaskSettlement,
        postNotification: Bool = true
    ) async {
        guard let known = records.first(where: {
            $0.lastRunTaskID == taskID && $0.status == .awaitingConfirmation
        }) else { return }
        guard var record = try? await taskRepository.loadSchedule(id: known.id),
              record.lastRunTaskID == taskID,
              record.status == .awaitingConfirmation
        else { return }

        switch outcome {
        case .completed:
            if let plan {
                record.setFrozenWorkPlan(plan)
                record.status = .armed
            } else {
                record.status = .needsFirstRun
            }
            record.lastStatus = "Finished"

        case .cancelled:
            record.status = .needsFirstRun
            record.lastStatus = "Plan wasn’t confirmed."

        case .failed(let message):
            record.status = .failed
            record.lastStatus = String(message.prefix(240))
            record.nextFireAt = nil
            record.updatedAt = .now
        }

        if record.status != .failed {
            let keptFutureFire = record.nextFireAt.map { $0 > Date.now } ?? false
            if keptFutureFire {
                record.updatedAt = .now
            } else {
                record.finishTiming(at: Date.now)
            }
        }
        do {
            guard try await persist(record) else { return }
        } catch {
            lastError = "Couldn’t update that schedule."
            return
        }

        guard postNotification else { return }
        let body: String
        switch outcome {
        case .completed:
            body = record.lastStatus ?? "Finished"

        case .cancelled:
            body = "Plan wasn’t confirmed."

        case .failed(let message):
            body = String(message.prefix(240))
        }
        ScheduleNotifier.post(
            ScheduleNotificationPayload(
                scheduleID: record.id,
                title: record.title,
                body: body,
                kind: .agent,
                projectID: record.projectID,
                taskID: taskID
            ),
            playsSound: true
        )
    }

    func scanDue() async {
        let now = Date.now
        let due: [ScheduleRecord]
        do {
            due = try await taskRepository.dueSchedules(at: now)
        } catch {
            lastError = "Couldn’t check due schedules."
            trigger.arm(records: records)
            return
        }
        for item in due where !queue.contains(item.id) {
            let afterWake = item.nextFireAt.map { now.timeIntervalSince($0) > 120 } ?? false
            enqueue(item.id, kind: item.kind, afterWake: afterWake)
        }
        trigger.arm(records: records)
        enqueueOverdue(now: now)
    }

    /// Resolves a relative working directory inside the schedule’s PathGuard sandbox.
    nonisolated static func resolveWorkingDirectory(
        _ raw: String?,
        policy: PathGuard.Policy
    ) throws -> URL {
        try ScheduleRunner.resolveWorkingDirectory(raw, policy: policy)
    }

    // MARK: - Queue

    private func enqueue(
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

    private func kick() {
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

    private func performQueuedJob(_ job: ScheduleJobToken) async {
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

    private enum ScheduledRunStart {
        case performed
        case skipped
        case unavailable
    }

    private func run(_ job: ScheduleJobToken) async -> ScheduledRunStart {
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

    private func postRunNotification(
        for record: ScheduleRecord,
        body: String,
        taskID: UUID?,
        notify: ScheduleNotify
    ) {
        let playsSound: Bool
        switch notify {
        case .none:
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
    private func commitAfterRun(
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

    private func scriptRunRecord(
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
    private func persist(_ record: ScheduleRecord, scriptRun: ScheduleRunRecord? = nil) async throws -> Bool {
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

    private func remember(_ record: ScheduleRecord) {
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

    private func forget(_ id: UUID) {
        records.removeAll { $0.id == id }
        queue.forget(id)
        publishQueue()
        trigger.arm(records: records)
    }

    private func publishQueue() {
        queuedIDs = queue.queuedIDs
        runningIDs = queue.runningIDs
    }

    /// Enqueues enabled recipes whose `nextFireAt` is already due (e.g. after a trial).
    private func enqueueOverdue(now: Date = .now, excluding excludedID: UUID? = nil) {
        for record in records where record.isDue(at: now) {
            if record.id == excludedID { continue }
            guard !queue.contains(record.id) else { continue }
            enqueue(record.id, kind: record.kind)
        }
    }

    private func reloadAndArmTimer() async {
        await reload()
        await scanDue()
    }
}
