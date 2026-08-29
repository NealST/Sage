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
    var records: [ScheduleRecord] = []
    /// Jobs waiting in the in-process queue (not yet executing).
    var queuedIDs: Set<UUID> = []
    /// Jobs currently executing.
    var runningIDs: Set<UUID> = []
    /// Last user-facing save / pause / delete / re-plan failure, if any.
    var lastError: String?

    var runningTitle: String? {
        records.first { runningIDs.contains($0.id) }?.title
            ?? records.first { queuedIDs.contains($0.id) }?.title
    }

    let taskRepository: any TaskRepository
    let queue = ScheduleJobQueue()
    let trigger: ScheduleTrigger
    let runner: ScheduleRunner
    /// IDs deleted this session; blocks in-flight upserts from recreating a row.
    var deletedIDs: Set<UUID> = []
    /// Unstructured beat tasks so Stop can cancel one job without draining others.
    var runTasks: [UUID: Task<Void, Never>] = [:]
    var processOwners: [UUID: UUID] = [:]

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
            Task { await self?.scanDue() }
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
            ToolAuthorizationGrantStore.shared.removeTaskGrants(
                scopeID: "schedule:\(id.uuidString)"
            )
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
            ToolAuthorizationGrantStore.shared.removeTaskGrants(
                scopeID: "schedule:\(id.uuidString)"
            )
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
}
