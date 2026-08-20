//
//  ScheduleTrigger.swift
//  Sage
//
//  Wall-clock timer + wake-from-sleep. Does not execute jobs.
//

import AppKit
import Foundation

/// Arms a one-shot wall timer for the soonest future `nextFireAt`.
@MainActor
final class ScheduleTrigger {
    private var timer: DispatchSourceTimer?
    private var wakeTask: Task<Void, Never>?
    var onFire: () -> Void = {}

    /// Starts observing `NSWorkspace.didWakeNotification`. Safe to call once.
    func startWakeObserver() {
        guard wakeTask == nil else { return }
        wakeTask = Task { [weak self] in
            let stream = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didWakeNotification
            )
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await self?.onFire()
            }
        }
    }

    /// Cancels the current timer and, if needed, schedules the next fire.
    func arm(records: [ScheduleRecord], now: Date = .now) {
        timer?.cancel()
        timer = nil
        guard let upcoming = ScheduleRecord.nextTimerFire(in: records, now: now) else { return }
        // Cap far-future sleeps so a missed wake still rescans within half a day.
        let delay = min(max(upcoming.timeIntervalSinceNow, 0.25), 12 * 3_600)
        let nanos = Int64((delay * 1_000_000_000).rounded())
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            wallDeadline: DispatchWallTime.now() + .nanoseconds(Int(clamping: nanos)),
            repeating: .never,
            leeway: .seconds(1)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.onFire()
            }
        }
        source.resume()
        timer = source
    }

    /// Drops the wall timer and wake observer so Quit does not fire a new beat.
    func disarm() {
        timer?.cancel()
        timer = nil
        wakeTask?.cancel()
        wakeTask = nil
    }
}
