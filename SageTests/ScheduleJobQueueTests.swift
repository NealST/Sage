@testable import Sage
import XCTest

@MainActor
final class ScheduleJobQueueTests: XCTestCase {
    func testEnqueueDedupesQueuedAndRunning() {
        let queue = ScheduleJobQueue()
        let id = UUID()
        XCTAssertTrue(queue.enqueue(id, kind: .script))
        XCTAssertFalse(queue.enqueue(id, kind: .script))
        XCTAssertTrue(queue.queuedIDs.contains(id))
        let jobs = queue.pumpStartable()
        XCTAssertEqual(jobs.map(\.id), [id])
        XCTAssertTrue(queue.runningIDs.contains(id))
        XCTAssertFalse(queue.enqueue(id, kind: .script, isTrial: true))
    }

    func testDequeueDoesNotCancelInFlightRun() {
        let queue = ScheduleJobQueue()
        let id = UUID()
        XCTAssertTrue(queue.enqueue(id, kind: .script, isTrial: true))
        let jobs = queue.pumpStartable()
        XCTAssertEqual(jobs.first?.id, id)
        XCTAssertEqual(jobs.first?.isTrial, true)
        queue.dequeue(id)
        XCTAssertTrue(queue.runningIDs.contains(id))
        XCTAssertFalse(queue.queuedIDs.contains(id))
        queue.finishCurrent(id)
        XCTAssertFalse(queue.contains(id))
    }

    func testPumpStartableConsumesAfterWakeAndTrialFlags() throws {
        let queue = ScheduleJobQueue()
        let id = UUID()
        _ = queue.enqueue(id, kind: .agent, afterWake: true, isTrial: true)
        let job = try XCTUnwrap(queue.pumpStartable().first)
        XCTAssertTrue(job.afterWake)
        XCTAssertTrue(job.isTrial)
        XCTAssertEqual(job.kind, .agent)
        XCTAssertTrue(queue.pumpStartable().isEmpty)
        XCTAssertFalse(queue.hasPending)
    }

    func testScriptsCanStartTogetherWhileAgentsStaySerial() {
        let queue = ScheduleJobQueue()
        let scriptA = UUID()
        let scriptB = UUID()
        let agentA = UUID()
        let agentB = UUID()
        _ = queue.enqueue(agentA, kind: .agent)
        _ = queue.enqueue(scriptA, kind: .script)
        _ = queue.enqueue(agentB, kind: .agent)
        _ = queue.enqueue(scriptB, kind: .script)

        let first = queue.pumpStartable()
        XCTAssertEqual(Set(first.map(\.id)), [agentA, scriptA, scriptB])
        XCTAssertTrue(queue.queuedIDs.contains(agentB))
        XCTAssertFalse(queue.runningIDs.contains(agentB))

        queue.finishCurrent(agentA)
        let second = queue.pumpStartable()
        XCTAssertEqual(second.map(\.id), [agentB])
    }

    func testScriptCapKeepsTheRestQueued() throws {
        let queue = ScheduleJobQueue()
        let ids = (0..<ScheduleJobQueue.maxConcurrentScripts + 1).map { _ in UUID() }
        for id in ids {
            _ = queue.enqueue(id, kind: .script)
        }
        let started = queue.pumpStartable()
        XCTAssertEqual(started.count, ScheduleJobQueue.maxConcurrentScripts)
        let overflowID = try XCTUnwrap(ids.last)
        XCTAssertTrue(queue.queuedIDs.contains(overflowID))
        XCTAssertEqual(queue.runningIDs.count, ScheduleJobQueue.maxConcurrentScripts)
    }

    func testNextTimerFireSkipsPausedAndPastDates() {
        let now = Date(timeIntervalSince1970: 1_000)
        let past = ScheduleRecord(
            title: "past",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .armed,
            nextFireAt: Date(timeIntervalSince1970: 500)
        )
        let paused = ScheduleRecord(
            title: "paused",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: false,
            status: .paused,
            nextFireAt: Date(timeIntervalSince1970: 1_500)
        )
        let awaiting = ScheduleRecord(
            title: "awaiting",
            kind: .agent,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .awaitingConfirmation,
            nextFireAt: Date(timeIntervalSince1970: 1_200)
        )
        let soon = ScheduleRecord(
            title: "soon",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .armed,
            nextFireAt: Date(timeIntervalSince1970: 1_400)
        )
        let later = ScheduleRecord(
            title: "later",
            kind: .script,
            cadence: .daily(hour: 9, minute: 0),
            enabled: true,
            status: .armed,
            nextFireAt: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertEqual(
            ScheduleRecord.nextTimerFire(in: [past, paused, awaiting, later, soon], now: now),
            soon.nextFireAt
        )
    }

    func testFinishTimingClearsOnceAndAdvancesInterval() {
        var once = ScheduleRecord(
            title: "once",
            kind: .script,
            cadence: .once(date: Date(timeIntervalSince1970: 2_000)),
            enabled: true,
            status: .armed,
            nextFireAt: Date(timeIntervalSince1970: 2_000)
        )
        once.finishTiming(at: Date(timeIntervalSince1970: 2_000))
        XCTAssertFalse(once.enabled)
        XCTAssertNil(once.nextFireAt)

        let from = Date(timeIntervalSince1970: 1_000)
        var interval = ScheduleRecord(
            title: "interval",
            kind: .script,
            cadence: .interval(seconds: 60),
            enabled: true,
            status: .armed,
            nextFireAt: from
        )
        interval.finishTiming(at: from)
        XCTAssertEqual(interval.nextFireAt, from.addingTimeInterval(60))
        XCTAssertTrue(interval.enabled)
    }

    func testStatusTextPrefixesWakeOnce() {
        XCTAssertEqual(ScheduleRecord.statusText("Done", afterWake: false), "Done")
        XCTAssertEqual(
            ScheduleRecord.statusText("Done", afterWake: true),
            "Ran after wake. Done"
        )
        XCTAssertEqual(
            ScheduleRecord.statusText("Ran after wake. Done", afterWake: true),
            "Ran after wake. Done"
        )
    }

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
