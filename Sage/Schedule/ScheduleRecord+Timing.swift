//
//  ScheduleRecord+Timing.swift
//  Sage
//

import Foundation

extension ScheduleRecord {
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
            return applyAgentOutcome(outcome, started: started, afterWake: afterWake, isTrial: isTrial)
        }
    }

    mutating func applyAgentOutcome(
        _ outcome: ScheduleAgentOutcome,
        started: Date,
        afterWake: Bool,
        isTrial: Bool
    ) -> String {
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

        case .finished(let succeeded, let summary, let plan, _):
            lastStatus = Self.statusText(summary, afterWake: afterWake)
            applyFinishedAgentRun(succeeded: succeeded, plan: plan, started: started, isTrial: isTrial)
            return lastStatus ?? summary
        }
    }

    mutating func applyFinishedAgentRun(
        succeeded: Bool,
        plan: WorkPlan?,
        started: Date,
        isTrial: Bool
    ) {
        if succeeded, let plan {
            setFrozenWorkPlan(plan)
            status = .armed
            completeSuccessfully(isTrial: isTrial)
        } else if succeeded {
            status = frozenWorkPlan == nil ? .needsFirstRun : .armed
            completeSuccessfully(isTrial: isTrial)
        } else {
            markFailed(at: started)
        }
    }

    mutating func markFailed(at now: Date) {
        status = .failed
        nextFireAt = nil
        updatedAt = now
    }

    mutating func completeSuccessfully(isTrial: Bool) {
        if isTrial {
            updatedAt = .now
        } else {
            finishTiming(at: .now)
        }
    }

    /// Stop does not consume a one-shot, and does not skip the next interval from a stale start time.
    mutating func parkAfterStop(isTrial: Bool) {
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
        let parts = trimmed.split(
            separator: "\n",
            maxSplits: 1,
            omittingEmptySubsequences: true
        )
        let firstLine = parts.first.map(String.init) ?? trimmed
        if firstLine.count <= 48 { return firstLine }
        let shortened = String(firstLine.prefix(45))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return shortened + "…"
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
    case finished(succeeded: Bool, summary: String, plan: WorkPlan?, taskID: UUID?)
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
            return .mute

        case .script(let outcome):
            if outcome.failed { return .sound }
            return (isTrial || cadence.playsSuccessSound) ? .sound : .silent

        case .agent(let outcome):
            switch outcome {
            case .degraded, .needsConfirmation:
                return .sound

            case .finished(let succeeded, _, _, _):
                if !succeeded { return .sound }
                return (isTrial || cadence.playsSuccessSound) ? .sound : .silent
            }
        }
    }
}

/// How loudly a finished beat should announce itself.
nonisolated enum ScheduleNotify: Sendable, Equatable {
    case mute
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
