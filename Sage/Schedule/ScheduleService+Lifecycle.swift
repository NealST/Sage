//
//  ScheduleService+Lifecycle.swift
//  Sage
//

import Foundation

extension ScheduleService {
    /// First-run `act` confirmation finished on a window session (not the ephemeral runner).
    func noteSpawnedTaskSettled(
        taskID: UUID,
        plan: WorkPlan?,
        outcome: AgentTaskSettlement,
        postNotification: Bool = true
    ) async {
        guard let known = records.first(where: { record in
            record.lastRunTaskID == taskID && record.status == .awaitingConfirmation
        }) else { return }
        guard var record = try? await taskRepository.loadSchedule(id: known.id),
              record.lastRunTaskID == taskID,
              record.status == .awaitingConfirmation
        else { return }

        applySettlement(&record, plan: plan, outcome: outcome)
        do {
            guard try await persist(record) else { return }
        } catch {
            lastError = "Couldn’t update that schedule."
            return
        }

        guard postNotification else { return }
        let body = settlementNotice(record: record, outcome: outcome)
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

    func applySettlement(
        _ record: inout ScheduleRecord,
        plan: WorkPlan?,
        outcome: AgentTaskSettlement
    ) {
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
        guard record.status != .failed else { return }
        let keptFutureFire = record.nextFireAt.map { $0 > Date.now } ?? false
        if keptFutureFire {
            record.updatedAt = .now
        } else {
            record.finishTiming(at: Date.now)
        }
    }

    func settlementNotice(record: ScheduleRecord, outcome: AgentTaskSettlement) -> String {
        switch outcome {
        case .completed:
            return record.lastStatus ?? "Finished"

        case .cancelled:
            return "Plan wasn’t confirmed."

        case .failed(let message):
            return String(message.prefix(240))
        }
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
}
