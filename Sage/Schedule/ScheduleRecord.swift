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

    /// Applies one beat’s result: fire metadata, status, cadence, and the notification body.
    @discardableResult
    mutating func applyRun(
        _ result: ScheduleBeatResult,
        started: Date,
        afterWake: Bool,
        isTrial: Bool
    ) -> String {
        lastFireAt = started
        switch result {
        case .stopped:
            lastStatus = Self.statusText("Stopped", afterWake: afterWake)
            parkAfterStop(isTrial: isTrial)
            return lastStatus ?? "Stopped"

        case .script(let outcome):
            lastStatus = Self.statusText(outcome.excerpt, afterWake: afterWake)
            if outcome.failed {
                markFailed(at: started)
            } else {
                status = .armed
                completeSuccessfully(isTrial: isTrial)
            }
            return lastStatus ?? outcome.excerpt

        case .agent(let outcome):
            if let taskID = outcome.taskID {
                lastRunTaskID = taskID
            }
            switch outcome {
            case .degraded(let reason):
                setFrozenWorkPlan(nil)
                status = .needsFirstRun
                lastStatus = Self.statusText(reason, afterWake: afterWake)
                completeSuccessfully(isTrial: isTrial)
                return "Needs setup. \(reason)"

            case .needsConfirmation(let taskID, _):
                lastRunTaskID = taskID
                status = .awaitingConfirmation
                lastStatus = Self.statusText("Needs confirmation", afterWake: afterWake)
                if !isTrial {
                    nextFireAt = nil
                }
                updatedAt = .now
                return "A schedule needs confirmation"

            case .finished(let ok, let summary, let plan, _):
                lastStatus = Self.statusText(summary, afterWake: afterWake)
                if ok, let plan {
                    setFrozenWorkPlan(plan)
                    status = .armed
                    completeSuccessfully(isTrial: isTrial)
                } else if ok {
                    status = frozenWorkPlan == nil ? .needsFirstRun : .armed
                    completeSuccessfully(isTrial: isTrial)
                } else {
                    markFailed(at: started)
                }
                return lastStatus ?? summary
            }
        }
    }

    private mutating func markFailed(at now: Date) {
        status = .failed
        nextFireAt = nil
        updatedAt = now
    }

    private mutating func completeSuccessfully(isTrial: Bool) {
        if isTrial {
            updatedAt = .now
        } else {
            finishTiming(at: .now)
        }
    }

    /// Stop does not consume a one-shot, and does not skip the next interval from a stale start time.
    private mutating func parkAfterStop(isTrial: Bool) {
        if isTrial {
            updatedAt = .now
            return
        }
        switch cadence {
        case .once, .delay:
            nextFireAt = nil
            updatedAt = .now

        case .interval, .weekdays, .daily:
            finishTiming(at: .now)
        }
    }

    /// Why an armed replay should fall back to a first run, or `nil` if replay is still valid.
    func replayDegradeReason(
        enabledSkillNames: Set<String>,
        projectRootExists: Bool?
    ) -> String? {
        if let projectRootExists, !projectRootExists {
            return "Project folder is gone."
        }
        let missing = frozenSkillNames.filter { !enabledSkillNames.contains($0) }
        if let name = missing.first {
            return "Skill “\(name)” is missing or off."
        }
        return nil
    }

    /// Short title for lists and notifications.
    static func makeTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Schedule" }
        let firstLine = trimmed.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: true
        ).first.map(String.init) ?? trimmed
        if firstLine.count <= 48 { return firstLine }
        return String(firstLine.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Confirmed agent recipe from the composer tip.
    static func agent(from draft: ScheduleDraft) -> Self {
        Self(
            title: makeTitle(from: draft.prompt),
            kind: .agent,
            projectID: draft.projectID,
            prompt: draft.prompt,
            cadence: draft.cadence.resolvedForSave(),
            enabled: true,
            status: .needsFirstRun,
            originTaskID: draft.originTaskID
        )
    }

    /// Script recipe from the window panel.
    static func script(
        command: String,
        cadence: ScheduleCadence,
        projectID: UUID?,
        workingDirectory: String? = nil
    ) -> Self {
        Self(
            title: makeTitle(from: command),
            kind: .script,
            projectID: projectID,
            command: command,
            workingDirectory: Self.normalizedWorkingDirectory(workingDirectory),
            cadence: cadence.resolvedForSave(),
            enabled: true,
            status: .armed
        )
    }

    /// Latest non-slash user request in a transcript. Ignores protected skill/system lines.
    static func latestUserRequest(in events: [AgentEvent]) -> String? {
        for event in events.reversed() where event.kind == .userInput {
            if event.protected { continue }
            let text = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text.hasPrefix("/") { continue }
            return text
        }
        return nil
    }

    /// Empty, `.`, or equivalent means the scope root.
    static func normalizedWorkingDirectory(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed == "." { return nil }
        return trimmed
    }

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
}

/// Composer tip before an agent schedule is saved.
nonisolated struct ScheduleDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var cadence: ScheduleCadence
    var prompt: String
    var projectID: UUID?
    var scopeLabel: String
    /// Set only when the user explicitly used this conversation as the prompt.
    var originTaskID: UUID?
    /// When true, Save also enqueues one trial run.
    var runOnceNow: Bool

    init(
        id: UUID = UUID(),
        cadence: ScheduleCadence,
        prompt: String,
        projectID: UUID?,
        scopeLabel: String,
        originTaskID: UUID? = nil,
        runOnceNow: Bool = false
    ) {
        self.id = id
        self.cadence = cadence
        self.prompt = prompt
        self.projectID = projectID
        self.scopeLabel = scopeLabel
        self.originTaskID = originTaskID
        self.runOnceNow = runOnceNow
    }
}

/// Result of one scheduled script invocation.
nonisolated struct ScheduleScriptOutcome: Sendable, Equatable {
    var excerpt: String
    var exitCode: Int32
    var failed: Bool
}

/// Result of one scheduled agent invocation.
nonisolated enum ScheduleAgentOutcome: Sendable, Equatable {
    case finished(ok: Bool, summary: String, plan: WorkPlan?, taskID: UUID?)
    case needsConfirmation(taskID: UUID, plan: WorkPlan?)
    case degraded(reason: String)

    var taskID: UUID? {
        switch self {
        case .finished(_, _, _, let taskID): return taskID
        case .needsConfirmation(let taskID, _): return taskID
        case .degraded: return nil
        }
    }
}

/// One beat’s outcome after the runner returns (or the user stops it).
nonisolated enum ScheduleBeatResult: Sendable, Equatable {
    case script(ScheduleScriptOutcome)
    case agent(ScheduleAgentOutcome)
    case stopped

    /// Whether to post a system notification, and whether it should play a sound.
    func notification(isTrial: Bool, cadence: ScheduleCadence) -> ScheduleNotify {
        switch self {
        case .stopped:
            return .none

        case .script(let outcome):
            if outcome.failed { return .sound }
            return (isTrial || cadence.playsSuccessSound) ? .sound : .silent

        case .agent(let outcome):
            switch outcome {
            case .degraded, .needsConfirmation:
                return .sound

            case .finished(let ok, _, _, _):
                if !ok { return .sound }
                return (isTrial || cadence.playsSuccessSound) ? .sound : .silent
            }
        }
    }
}

/// How loudly a finished beat should announce itself.
nonisolated enum ScheduleNotify: Sendable, Equatable {
    case none
    case silent
    case sound
}

/// One script execution stored in `schedule_runs`.
nonisolated struct ScheduleRunRecord: Identifiable, Sendable, Equatable {
    let id: UUID
    let scheduleID: UUID
    let startedAt: Date
    let endedAt: Date?
    let exitCode: Int32?
    let outputExcerpt: String?
}

extension ScheduleRecord {
    /// Same order as SQL: next fire first, nulls last, then newest update.
    static func sortedForListing(_ records: [ScheduleRecord]) -> [ScheduleRecord] {
        records.sorted { lhs, rhs in
            switch (lhs.nextFireAt, rhs.nextFireAt) {
            case (nil, nil):
                return lhs.updatedAt > rhs.updatedAt

            case (nil, _):
                return false

            case (_, nil):
                return true

            case (let left?, let right?):
                if left != right { return left < right }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }
}
