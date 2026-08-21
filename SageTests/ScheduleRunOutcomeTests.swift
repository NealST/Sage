@testable import Sage
import XCTest

final class ScheduleRunOutcomeTests: XCTestCase {
    func testApplyRunScriptFailureClearsNextFire() {
        var record = ScheduleRecord(
            title: "script",
            kind: .script,
            cadence: .interval(seconds: 60),
            enabled: true,
            status: .armed,
            nextFireAt: Date(timeIntervalSince1970: 2_000)
        )
        let body = record.applyRun(
            .script(ScheduleScriptOutcome(excerpt: "Failed: boom", exitCode: 1, failed: true)),
            started: Date(timeIntervalSince1970: 1_000),
            afterWake: false,
            isTrial: false
        )
        XCTAssertEqual(body, "Failed: boom")
        XCTAssertEqual(record.status, .failed)
        XCTAssertNil(record.nextFireAt)
    }

    func testApplyRunTrialDoesNotAdvanceCadence() {
        let fire = Date(timeIntervalSince1970: 2_000)
        var record = ScheduleRecord(
            title: "script",
            kind: .script,
            cadence: .interval(seconds: 60),
            enabled: true,
            status: .armed,
            nextFireAt: fire
        )
        _ = record.applyRun(
            .script(ScheduleScriptOutcome(excerpt: "ok", exitCode: 0, failed: false)),
            started: Date(timeIntervalSince1970: 1_000),
            afterWake: false,
            isTrial: true
        )
        XCTAssertEqual(record.status, .armed)
        XCTAssertEqual(record.nextFireAt, fire)
        XCTAssertTrue(record.enabled)
    }

    func testApplyRunStoppedSkipsThisBeat() throws {
        let started = Date(timeIntervalSince1970: 1_000)
        var record = ScheduleRecord(
            title: "script",
            kind: .script,
            cadence: .interval(seconds: 60),
            enabled: true,
            status: .armed,
            nextFireAt: started
        )
        let body = record.applyRun(
            .stopped,
            started: started,
            afterWake: true,
            isTrial: false
        )
        XCTAssertEqual(body, "Ran after wake. Stopped")
        XCTAssertEqual(record.status, .armed)
        let next = try XCTUnwrap(record.nextFireAt)
        XCTAssertGreaterThan(next.timeIntervalSinceNow, 50)
        XCTAssertLessThan(next.timeIntervalSinceNow, 70)
        XCTAssertNotEqual(record.lastStatus?.contains("Failed"), true)
    }

    func testApplyRunIntervalAdvancesFromCompletionNotStart() throws {
        let started = Date.now.addingTimeInterval(-180)
        var record = ScheduleRecord(
            title: "script",
            kind: .script,
            cadence: .interval(seconds: 60),
            enabled: true,
            status: .armed,
            nextFireAt: started
        )
        _ = record.applyRun(
            .script(ScheduleScriptOutcome(excerpt: "ok", exitCode: 0, failed: false)),
            started: started,
            afterWake: false,
            isTrial: false
        )
        let next = try XCTUnwrap(record.nextFireAt)
        XCTAssertGreaterThan(next.timeIntervalSinceNow, 50)
        XCTAssertLessThan(next.timeIntervalSinceNow, 70)
        XCTAssertGreaterThan(next, started.addingTimeInterval(60))
    }

    func testApplyRunStoppedDoesNotConsumeOnce() {
        let fire = Date(timeIntervalSince1970: 2_000)
        var record = ScheduleRecord(
            title: "once",
            kind: .script,
            cadence: .once(date: fire),
            enabled: true,
            status: .armed,
            nextFireAt: fire
        )
        _ = record.applyRun(
            .stopped,
            started: fire,
            afterWake: false,
            isTrial: false
        )
        XCTAssertTrue(record.enabled)
        XCTAssertNil(record.nextFireAt)
        XCTAssertEqual(record.status, .armed)
    }

    func testApplyRunAgentNeedsConfirmation() {
        let taskID = UUID()
        var record = ScheduleRecord(
            title: "agent",
            kind: .agent,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .needsFirstRun,
            nextFireAt: Date(timeIntervalSince1970: 2_000)
        )
        let body = record.applyRun(
            .agent(.needsConfirmation(taskID: taskID, plan: nil)),
            started: Date(timeIntervalSince1970: 1_000),
            afterWake: false,
            isTrial: false
        )
        XCTAssertEqual(body, "A schedule needs confirmation")
        XCTAssertEqual(record.status, .awaitingConfirmation)
        XCTAssertEqual(record.lastRunTaskID, taskID)
        XCTAssertNil(record.nextFireAt)
    }

    func testSortedForRecentsPutsUserThreadsFirst() {
        let user = TaskSummary(
            id: UUID(),
            status: .active,
            projectID: nil,
            summary: "User thread",
            topic: nil,
            abstract: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let scheduled = TaskSummary(
            id: UUID(),
            status: .active,
            projectID: nil,
            summary: "Scheduled run",
            topic: nil,
            abstract: nil,
            updatedAt: Date(timeIntervalSince1970: 9),
            originScheduleID: UUID()
        )
        let sorted = TaskSummary.sortedForRecents([scheduled, user])
        XCTAssertEqual(sorted.map(\.id), [user.id, scheduled.id])
        XCTAssertEqual(scheduled.recentsMenuTitle, "Scheduled · Scheduled run")
        XCTAssertEqual(user.recentsMenuTitle, "User thread")
    }

    func testStoppedBeatDoesNotNotify() {
        XCTAssertEqual(
            ScheduleBeatResult.stopped.notification(
                isTrial: false,
                cadence: .interval(seconds: 60)
            ),
            .mute
        )
        XCTAssertEqual(
            ScheduleBeatResult.stopped.notification(
                isTrial: true,
                cadence: .daily(hour: 9, minute: 0)
            ),
            .mute
        )
    }

    func testIntervalSuccessIsSilentUnlessTrial() {
        let success = ScheduleBeatResult.script(
            ScheduleScriptOutcome(excerpt: "ok", exitCode: 0, failed: false)
        )
        XCTAssertEqual(
            success.notification(isTrial: false, cadence: .interval(seconds: 60)),
            .silent
        )
        XCTAssertEqual(
            success.notification(isTrial: true, cadence: .interval(seconds: 60)),
            .sound
        )
        XCTAssertEqual(
            success.notification(isTrial: false, cadence: .daily(hour: 9, minute: 0)),
            .sound
        )
    }

    func testFailureAndConfirmationAlwaysSound() {
        let failed = ScheduleBeatResult.script(
            ScheduleScriptOutcome(excerpt: "Failed", exitCode: 1, failed: true)
        )
        XCTAssertEqual(
            failed.notification(isTrial: false, cadence: .interval(seconds: 60)),
            .sound
        )
        XCTAssertEqual(
            ScheduleBeatResult.agent(.needsConfirmation(taskID: UUID(), plan: nil))
                .notification(isTrial: false, cadence: .interval(seconds: 60)),
            .sound
        )
        XCTAssertEqual(
            ScheduleBeatResult.agent(.degraded(reason: "gone"))
                .notification(isTrial: false, cadence: .interval(seconds: 60)),
            .sound
        )
    }

    func testShellCommandPolicyBlocksSudoAndForkBomb() {
        XCTAssertThrowsError(try ShellCommandPolicy.validate("sudo ls"))
        XCTAssertThrowsError(try ShellCommandPolicy.validate("echo hi; sudo -s"))
        XCTAssertThrowsError(try ShellCommandPolicy.validate(":(){:|:&};:"))
        XCTAssertNoThrow(try ShellCommandPolicy.validate("git status"))
    }
}
