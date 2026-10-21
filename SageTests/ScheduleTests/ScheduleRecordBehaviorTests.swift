@testable import Sage
import XCTest

final class ScheduleRecordBehaviorTests: XCTestCase {
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
        let laterRecord = ScheduleRecord(
            title: "a",
            kind: .script,
            cadence: .once(date: later),
            nextFireAt: later,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let earlierRecord = ScheduleRecord(
            title: "b",
            kind: .script,
            cadence: .once(date: early),
            nextFireAt: early,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let nullLater = ScheduleRecord(
            title: "c",
            kind: .script,
            cadence: .once(date: early),
            nextFireAt: nil,
            updatedAt: Date(timeIntervalSince1970: 9)
        )
        let nullEarlier = ScheduleRecord(
            title: "d",
            kind: .script,
            cadence: .once(date: early),
            nextFireAt: nil,
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        XCTAssertEqual(
            ScheduleRecord.sortedForListing([laterRecord, nullLater, earlierRecord, nullEarlier]).map(\.title),
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
