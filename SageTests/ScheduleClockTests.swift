import XCTest
@testable import Sage

final class ScheduleClockTests: XCTestCase {
    func testOnceInThePastReturnsNil() {
        let past = Date().addingTimeInterval(-60)
        XCTAssertNil(ScheduleClock.nextFireDate(for: .once(date: past), after: .now))
    }

    func testOnceInTheFutureReturnsThatDate() {
        let future = Date().addingTimeInterval(120)
        let next = ScheduleClock.nextFireDate(for: .once(date: future), after: .now)
        XCTAssertEqual(next, future)
    }

    func testIntervalUsesAtLeastSixtySeconds() {
        let from = Date(timeIntervalSince1970: 1_000_000)
        let next = ScheduleClock.nextFireDate(for: .interval(seconds: 10), after: from)
        XCTAssertEqual(next, from.addingTimeInterval(60))
    }

    func testWeekdaysSameMorningFiresToday() throws {
        let from = try date(year: 2026, month: 8, day: 17, hour: 8, minute: 0) // Monday
        let next = try XCTUnwrap(
            ScheduleClock.nextFireDate(for: .weekdays(hour: 9, minute: 0), after: from)
        )
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: next)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 8)
        XCTAssertEqual(parts.day, 17)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(parts.weekday, 2)
    }

    func testWeekdaysAfterNineGoesToNextWeekday() throws {
        let from = try date(year: 2026, month: 8, day: 17, hour: 9, minute: 0)
        let next = try XCTUnwrap(
            ScheduleClock.nextFireDate(for: .weekdays(hour: 9, minute: 0), after: from)
        )
        let parts = Calendar.current.dateComponents([.day, .weekday, .hour, .minute], from: next)
        XCTAssertEqual(parts.day, 18)
        XCTAssertEqual(parts.weekday, 3)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 0)
    }

    func testFridayEveningGoesToMonday() throws {
        let from = try date(year: 2026, month: 8, day: 21, hour: 18, minute: 0) // Friday
        let next = try XCTUnwrap(
            ScheduleClock.nextFireDate(for: .weekdays(hour: 9, minute: 0), after: from)
        )
        let parts = Calendar.current.dateComponents([.day, .weekday, .hour], from: next)
        XCTAssertEqual(parts.day, 24)
        XCTAssertEqual(parts.weekday, 2)
        XCTAssertEqual(parts.hour, 9)
    }

    func testOnceCadenceDoesNotRescheduleAfterRun() {
        let future = Date().addingTimeInterval(3600)
        XCTAssertNil(ScheduleClock.nextFireDateAfterRun(for: .once(date: future)))
        XCTAssertNil(ScheduleClock.nextFireDateAfterRun(for: .delay(seconds: 3600)))
    }

    func testIntervalAfterRunUsesCompletionInstant() {
        let started = Date(timeIntervalSince1970: 1_000)
        let completed = started.addingTimeInterval(180)
        let next = ScheduleClock.nextFireDateAfterRun(
            for: .interval(seconds: 60),
            from: completed
        )
        XCTAssertEqual(next, completed.addingTimeInterval(60))
        XCTAssertGreaterThan(next ?? .distantPast, started.addingTimeInterval(60))
    }

    func testParserWeekdaysWithPrompt() {
        let parsed = ScheduleCadenceParser.parseAgentArgument("weekdays 9:00 write the standup")
        XCTAssertEqual(parsed?.cadence, .weekdays(hour: 9, minute: 0))
        XCTAssertEqual(parsed?.prompt, "write the standup")
    }

    func testParserEveryMorning() {
        let parsed = ScheduleCadenceParser.parseAgentArgument("every morning check mail")
        XCTAssertEqual(parsed?.cadence, .daily(hour: 9, minute: 0))
        XCTAssertEqual(parsed?.prompt, "check mail")
    }

    func testParserDailyWithClock() {
        let parsed = ScheduleCadenceParser.parseAgentArgument("daily 14:30 review diffs")
        XCTAssertEqual(parsed?.cadence, .daily(hour: 14, minute: 30))
        XCTAssertEqual(parsed?.prompt, "review diffs")
    }

    func testParserInOneHour() {
        let parsed = ScheduleCadenceParser.parseAgentArgument("in 1 hour ping the server")
        XCTAssertEqual(parsed?.prompt, "ping the server")
        guard case .delay(let seconds) = parsed?.cadence else {
            return XCTFail("expected delay cadence until Save")
        }
        XCTAssertEqual(seconds, 3600, accuracy: 0.5)
    }

    func testDelayResolvesAtSaveTime() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(
            ScheduleCadence.delay(seconds: 3600).resolvedForSave(now: now),
            .once(date: now.addingTimeInterval(3600))
        )
        let record = ScheduleRecord.agent(
            from: ScheduleDraft(
                cadence: .delay(seconds: 3600),
                prompt: "ping",
                projectID: nil,
                scopeLabel: "General"
            )
        )
        guard case .once(let date) = record.cadence else {
            return XCTFail("agent save should persist an absolute once date")
        }
        XCTAssertGreaterThan(date.timeIntervalSinceNow, 3500)
        XCTAssertLessThan(date.timeIntervalSinceNow, 3700)
    }

    func testParserRequiresPrompt() {
        XCTAssertNil(ScheduleCadenceParser.parseAgentArgument("weekdays 9:00"))
        XCTAssertNil(ScheduleCadenceParser.parseAgentArgument("daily"))
        XCTAssertNil(ScheduleCadenceParser.parseAgentArgument("in 1 hour"))
    }

    func testParserAllowsEmptyPromptForCadenceOnly() {
        let weekdays = ScheduleCadenceParser.parseCadenceAndPrompt("weekdays 9:00")
        XCTAssertEqual(weekdays?.cadence, .weekdays(hour: 9, minute: 0))
        XCTAssertEqual(weekdays?.prompt, "")

        let once = ScheduleCadenceParser.parseCadenceAndPrompt("in 1 hour")
        XCTAssertEqual(once?.prompt, "")
        if case .delay(let seconds) = once?.cadence {
            XCTAssertEqual(seconds, 3600, accuracy: 0.5)
        } else {
            XCTFail("expected delay cadence")
        }
    }

    func testLatestUserRequestSkipsSlashAndProtected() {
        let events = [
            AgentEvent(kind: .userInput, content: "/remember foo", protected: false),
            AgentEvent(kind: .userInput, content: "[Activated skill: git]", protected: true),
            AgentEvent(kind: .userInput, content: "summarize yesterday’s diffs", protected: false),
            AgentEvent(kind: .assistantResponse, content: "Done"),
        ]
        XCTAssertEqual(
            ScheduleRecord.latestUserRequest(in: events),
            "summarize yesterday’s diffs"
        )
        XCTAssertNil(ScheduleRecord.latestUserRequest(in: [
            AgentEvent(kind: .userInput, content: "/schedule weekdays 9:00 this"),
        ]))
    }

    func testWorkingDirectoryNormalization() {
        XCTAssertNil(ScheduleRecord.normalizedWorkingDirectory(nil))
        XCTAssertNil(ScheduleRecord.normalizedWorkingDirectory("."))
        XCTAssertNil(ScheduleRecord.normalizedWorkingDirectory("  .  "))
        XCTAssertEqual(ScheduleRecord.normalizedWorkingDirectory("scripts"), "scripts")
    }

    func testAwaitingConfirmationStatusRawValue() {
        XCTAssertEqual(ScheduleStatus.awaitingConfirmation.rawValue, "awaiting_confirmation")
    }

    func testWorkingDirectoryDotResolvesInsideHome() throws {
        let url = try ScheduleService.resolveWorkingDirectory(".", policy: .home)
        XCTAssertEqual(
            url.resolvingSymlinksInPath().path,
            FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        )
    }

    func testAutocompleteAfterCommandAndSpace() {
        let empty = ScheduleCadenceParser.autocompleteInserts(forDraft: "/schedule")
        XCTAssertEqual(empty.map(\.insert), ScheduleCadenceParser.presets.map(\.insert))

        let spaced = ScheduleCadenceParser.autocompleteInserts(forDraft: "/schedule ")
        XCTAssertEqual(spaced.map(\.insert), ScheduleCadenceParser.presets.map(\.insert))

        let partial = ScheduleCadenceParser.autocompleteInserts(forDraft: "/schedule week")
        XCTAssertEqual(partial.map(\.insert), ["weekdays 9:00"])
    }

    func testAutocompleteHidesOncePromptIsPresent() {
        let done = ScheduleCadenceParser.autocompleteInserts(
            forDraft: "/schedule weekdays 9:00 write standup"
        )
        XCTAssertTrue(done.isEmpty)
    }

    func testCadenceFromPresetIsRelativeAtSaveTime() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(
            ScheduleCadenceParser.cadence(fromPresetInsert: "weekdays 9:00"),
            .weekdays(hour: 9, minute: 0)
        )
        XCTAssertEqual(
            ScheduleCadenceParser.cadence(fromPresetInsert: "in 1 hour", now: now),
            .once(date: now.addingTimeInterval(3600))
        )
    }

    func testTitleTruncatesFirstLine() {
        XCTAssertEqual(ScheduleRecord.makeTitle(from: "  short  "), "short")
        let long = String(repeating: "a", count: 60)
        let title = ScheduleRecord.makeTitle(from: long)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertEqual(title.count, 46)
    }

    func testReplayDegradeWhenProjectFolderIsGone() {
        let record = ScheduleRecord(
            title: "Standup",
            kind: .agent,
            cadence: .daily(hour: 9, minute: 0)
        )
        XCTAssertEqual(
            record.replayDegradeReason(enabledSkillNames: [], projectRootExists: false),
            "Project folder is gone."
        )
        XCTAssertNil(
            record.replayDegradeReason(enabledSkillNames: [], projectRootExists: true)
        )
        XCTAssertNil(
            record.replayDegradeReason(enabledSkillNames: [], projectRootExists: nil)
        )
    }

    func testReplayDegradeWhenFrozenSkillIsMissing() {
        let record = ScheduleRecord(
            title: "Standup",
            kind: .agent,
            cadence: .daily(hour: 9, minute: 0),
            frozenSkillNames: ["git-standup"]
        )
        XCTAssertEqual(
            record.replayDegradeReason(enabledSkillNames: ["other"], projectRootExists: true),
            "Skill “git-standup” is missing or off."
        )
        XCTAssertNil(
            record.replayDegradeReason(
                enabledSkillNames: ["git-standup"],
                projectRootExists: true
            )
        )
    }

    func testNotificationPayloadRoundTrip() {
        let scheduleID = UUID()
        let taskID = UUID()
        let projectID = UUID()
        let payload = ScheduleNotificationPayload(
            scheduleID: scheduleID,
            title: "Standup",
            body: "Done",
            kind: .agent,
            projectID: projectID,
            taskID: taskID
        )
        let decoded = ScheduleNotificationPayload.fromUserInfo(payload.userInfo)
        XCTAssertEqual(decoded?.scheduleID, scheduleID)
        XCTAssertEqual(decoded?.taskID, taskID)
        XCTAssertEqual(decoded?.projectID, projectID)
        XCTAssertEqual(decoded?.kind, .agent)
        XCTAssertNil(ScheduleNotificationPayload.fromUserInfo(["unrelated": "1"]))
    }

    func testListingSortPutsSoonestFireFirstAndNullsLast() {
        let early = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let a = ScheduleRecord(
            title: "a",
            kind: .script,
            cadence: .once(date: later),
            nextFireAt: later,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let b = ScheduleRecord(
            title: "b",
            kind: .script,
            cadence: .once(date: early),
            nextFireAt: early,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let c = ScheduleRecord(
            title: "c",
            kind: .script,
            cadence: .once(date: early),
            nextFireAt: nil,
            updatedAt: Date(timeIntervalSince1970: 9)
        )
        let d = ScheduleRecord(
            title: "d",
            kind: .script,
            cadence: .once(date: early),
            nextFireAt: nil,
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        XCTAssertEqual(
            ScheduleRecord.sortedForListing([a, c, b, d]).map(\.title),
            ["b", "a", "c", "d"]
        )
    }

    func testAllowsRunnerStartRequiresEnabledArmedOrFirstRun() {
        var record = ScheduleRecord(
            title: "Job",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .armed
        )
        XCTAssertTrue(record.allowsRunnerStart)

        record.enabled = false
        XCTAssertFalse(record.allowsRunnerStart)

        record.enabled = true
        record.status = .paused
        XCTAssertFalse(record.allowsRunnerStart)

        record.status = .awaitingConfirmation
        XCTAssertFalse(record.allowsRunnerStart)

        record.status = .failed
        XCTAssertFalse(record.allowsRunnerStart)

        record.status = .needsFirstRun
        XCTAssertTrue(record.allowsRunnerStart)
    }

    func testIsDueWhenNextFireIsPastAndRunnable() {
        let now = Date(timeIntervalSince1970: 1_000)
        let due = ScheduleRecord(
            title: "Due",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .armed,
            nextFireAt: Date(timeIntervalSince1970: 900)
        )
        XCTAssertTrue(due.isDue(at: now))

        let future = ScheduleRecord(
            title: "Later",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .armed,
            nextFireAt: Date(timeIntervalSince1970: 1_100)
        )
        XCTAssertFalse(future.isDue(at: now))

        let paused = ScheduleRecord(
            title: "Paused",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: false,
            status: .paused,
            nextFireAt: Date(timeIntervalSince1970: 900)
        )
        XCTAssertFalse(paused.isDue(at: now))

        let noFire = ScheduleRecord(
            title: "Once",
            kind: .script,
            cadence: .once(date: now),
            enabled: true,
            status: .armed,
            nextFireAt: nil
        )
        XCTAssertFalse(noFire.isDue(at: now))
    }

    func testAdoptingRunMetadataKeepsReplanStatusText() {
        let snapshot = Date(timeIntervalSince1970: 10)
        var live = ScheduleRecord(
            title: "Standup",
            kind: .agent,
            cadence: .daily(hour: 9, minute: 0),
            status: .needsFirstRun,
            lastFireAt: nil,
            lastStatus: "Needs setup — next run will re-plan.",
            lastRunTaskID: nil,
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        let result = ScheduleRecord(
            title: "Standup",
            kind: .agent,
            cadence: .daily(hour: 9, minute: 0),
            status: .armed,
            lastFireAt: Date(timeIntervalSince1970: 40),
            lastStatus: "Finished",
            lastRunTaskID: UUID(),
            updatedAt: snapshot
        )
        XCTAssertTrue(live.updatedAt > snapshot)
        live = live.adoptingRunMetadata(from: result, now: Date(timeIntervalSince1970: 60))
        XCTAssertEqual(live.lastStatus, "Needs setup — next run will re-plan.")
        XCTAssertEqual(live.lastFireAt, result.lastFireAt)
        XCTAssertEqual(live.lastRunTaskID, result.lastRunTaskID)
        XCTAssertEqual(live.status, .needsFirstRun)
        XCTAssertEqual(live.updatedAt, Date(timeIntervalSince1970: 60))
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return try XCTUnwrap(Calendar.current.date(from: components))
    }
}
