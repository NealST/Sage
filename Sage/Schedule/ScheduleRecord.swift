//
//  ScheduleRecord.swift
//  Sage
//
//  Persistent recipe for a timed job (not a Task).
//

import Foundation

nonisolated enum ScheduleKind: String, Codable, Sendable, Equatable {
    case agent
    case script
}

nonisolated enum ScheduleStatus: String, Codable, Sendable, Equatable {
    case draft
    case needsFirstRun = "needs_first_run"
    /// First-run `act` plan is waiting on the spawned task (not the user’s current chat).
    case awaitingConfirmation = "awaiting_confirmation"
    case armed
    case paused
    case failed
}

/// When a schedule fires. Wall-clock, system time zone.
nonisolated enum ScheduleCadence: Codable, Sendable, Equatable {
    /// Fire once at `date`.
    case once(date: Date)
    /// Fire every `seconds` after the last run (minimum 60s).
    case interval(seconds: TimeInterval)
    /// Monday–Friday at local `hour`:`minute`.
    case weekdays(hour: Int, minute: Int)
    /// Every day at local `hour`:`minute`.
    case daily(hour: Int, minute: Int)
    /// Fire once, `seconds` after save (resolved to `once` when persisted).
    case delay(seconds: TimeInterval)

    var shortLabel: String {
        switch self {
        case .once(let date):
            return date.formatted(date: .abbreviated, time: .shortened)

        case .interval(let seconds):
            let minutes = max(1, Int((seconds / 60).rounded()))
            return "Every \(minutes) min"

        case .weekdays(let hour, let minute):
            return "Weekdays \(Self.clockLabel(hour: hour, minute: minute))"

        case .daily(let hour, let minute):
            return "Daily \(Self.clockLabel(hour: hour, minute: minute))"

        case .delay(let seconds):
            let minutes = max(1, Int((seconds / 60).rounded()))
            if minutes == 60 { return "In 1 hour" }
            return "In \(minutes) min"
        }
    }

    /// Turns a relative delay into an absolute `once` date. Call at Save, not parse.
    func resolvedForSave(now: Date = .now) -> Self {
        switch self {
        case .delay(let seconds):
            return .once(date: now.addingTimeInterval(seconds))

        default:
            return self
        }
    }

    /// Interval success is expected often; once/daily/weekdays keep a sound.
    var playsSuccessSound: Bool {
        switch self {
        case .interval:
            return false

        case .once, .delay, .weekdays, .daily:
            return true
        }
    }

    private static func clockLabel(hour: Int, minute: Int) -> String {
        String(format: "%d:%02d", hour, minute)
    }
}

nonisolated struct ScheduleRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var title: String
    var kind: ScheduleKind
    var projectID: UUID?
    var prompt: String?
    var command: String?
    /// Script working directory relative to the scope root (`.` or nil = root).
    var workingDirectory: String?
    var cadence: ScheduleCadence
    var enabled: Bool
    var status: ScheduleStatus
    var nextFireAt: Date?
    var lastFireAt: Date?
    var lastStatus: String?
    var frozenWorkPlanJSON: String?
    var frozenSkillNames: [String]
    var originTaskID: UUID?
    /// Last spawned agent task for this schedule (notification / Open).
    var lastRunTaskID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: ScheduleKind,
        projectID: UUID? = nil,
        prompt: String? = nil,
        command: String? = nil,
        workingDirectory: String? = nil,
        cadence: ScheduleCadence,
        enabled: Bool = true,
        status: ScheduleStatus = .needsFirstRun,
        nextFireAt: Date? = nil,
        lastFireAt: Date? = nil,
        lastStatus: String? = nil,
        frozenWorkPlanJSON: String? = nil,
        frozenSkillNames: [String] = [],
        originTaskID: UUID? = nil,
        lastRunTaskID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.projectID = projectID
        self.prompt = prompt
        self.command = command
        self.workingDirectory = Self.normalizedWorkingDirectory(workingDirectory)
        self.cadence = cadence
        self.enabled = enabled
        self.status = status
        self.nextFireAt = nextFireAt
        self.lastFireAt = lastFireAt
        self.lastStatus = lastStatus
        self.frozenWorkPlanJSON = frozenWorkPlanJSON
        self.frozenSkillNames = frozenSkillNames
        self.originTaskID = originTaskID
        self.lastRunTaskID = lastRunTaskID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var frozenWorkPlan: WorkPlan? {
        guard let frozenWorkPlanJSON,
              let data = frozenWorkPlanJSON.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(WorkPlan.self, from: data)
    }

    mutating func setFrozenWorkPlan(_ plan: WorkPlan?) {
        guard let plan,
              let data = try? JSONEncoder().encode(plan),
              let json = String(data: data, encoding: .utf8)
        else {
            frozenWorkPlanJSON = nil
            frozenSkillNames = []
            return
        }
        frozenWorkPlanJSON = json
        frozenSkillNames = plan.skillNames
    }

    /// Whether the in-process runner may start this recipe.
    var allowsRunnerStart: Bool {
        enabled && (status == .needsFirstRun || status == .armed)
    }

    /// Whether the wall-clock timer should consider this recipe’s `nextFireAt`.
    var allowsTimerArming: Bool {
        enabled && status != .paused && status != .awaitingConfirmation
    }

    /// Whether wall-clock `nextFireAt` is due and the recipe is eligible to fire.
    func isDue(at now: Date) -> Bool {
        guard allowsRunnerStart, let nextFireAt else { return false }
        return nextFireAt <= now
    }

    /// Soonest future fire among recipes the timer should wait for.
    static func nextTimerFire(in records: [Self], now: Date = .now) -> Date? {
        records
            .filter(\.allowsTimerArming)
            .compactMap(\.nextFireAt)
            .filter { $0 > now }
            .min()
    }

    /// Prefixes wake context onto a one-line status.
    static func statusText(_ text: String, afterWake: Bool) -> String {
        guard afterWake else { return text }
        if text.hasPrefix("Ran after wake") { return text }
        return "Ran after wake. \(text)"
    }

    /// Advances or clears `nextFireAt` after a successful non-trial run.
    /// Pass the completion instant so an interval beat longer than the cadence
    /// cannot immediately re-queue.
    mutating func finishTiming(at now: Date) {
        switch cadence {
        case .once, .delay:
            enabled = false
            nextFireAt = nil

        case .interval, .weekdays, .daily:
            nextFireAt = ScheduleClock.nextFireDateAfterRun(for: cadence, from: now)
        }
        updatedAt = now
    }

    /// Copies fire metadata from a finished run without replacing Pause / Re-plan fields.
    func adoptingRunMetadata(from result: Self, now: Date = .now) -> Self {
        var next = self
        next.lastFireAt = result.lastFireAt
        next.lastRunTaskID = result.lastRunTaskID
        next.updatedAt = now
        return next
    }
}
