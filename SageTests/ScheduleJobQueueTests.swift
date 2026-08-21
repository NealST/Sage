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
}
