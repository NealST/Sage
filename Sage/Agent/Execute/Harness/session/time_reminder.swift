//
//  time_reminder.swift
//  Sage
//
//  Port of codex-rs/core/src/session/time_reminder.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import CodexCore
import CodexProtocol
import Foundation

struct CurrentTimeReminderState: Equatable, Sendable {
    var lastDeliveryTime: Date?
    var lastWindowId: String?
    var pendingUserOrToolOutputBoundary: Bool

    init(
        lastDeliveryTime: Date? = nil,
        lastWindowId: String? = nil,
        pendingUserOrToolOutputBoundary: Bool = false
    ) {
        self.lastDeliveryTime = lastDeliveryTime
        self.lastWindowId = lastWindowId
        self.pendingUserOrToolOutputBoundary = pendingUserOrToolOutputBoundary
    }

    mutating func noteRecordedItems(_ items: [ResponseItem]) {
        if items.contains(where: { item in
            isUserTurnBoundary(item)
                || {
                    switch item {
                    case .functionCallOutput, .customToolCallOutput, .toolSearchOutput:
                        return true
                    default:
                        return false
                    }
                }()
        }) {
            pendingUserOrToolOutputBoundary = true
        }
    }

    mutating func takeReminderDue(
        windowId: String,
        currentTime: Date,
        intervalSeconds: UInt64,
        afterUserOrToolOutput: Bool
    ) -> Bool {
        let isNewWindow = lastWindowId != windowId
        let followsBoundary = pendingUserOrToolOutputBoundary
        pendingUserOrToolOutputBoundary = false
        if afterUserOrToolOutput && !isNewWindow && !followsBoundary {
            return false
        }
        if let lastDeliveryTime,
           currentTime.timeIntervalSince(lastDeliveryTime) < Double(intervalSeconds),
           !isNewWindow {
            return false
        }
        lastDeliveryTime = currentTime
        lastWindowId = windowId
        return true
    }
}

func applyPersistentTimeReminderDefaults(_ config: inout Config) {
    if config.currentTimeReminder != nil { return }
    if config.features.enabled(.currentTimeReminder) {
        config.currentTimeReminder = CurrentTimeReminderConfig(sleepTool: true)
    }
}

func maybeRecordCurrentTimeReminder(
    sess: Session,
    turnContext: TurnContext,
    windowId: String,
    now: Date = Date()
) throws {
    let features = turnContext.config.features
    guard features.enabled(.currentTimeReminder) || sess.features.enabled(.currentTimeReminder) else {
        return
    }
    applyPersistentTimeReminderDefaults(&turnContext.config)
    guard let config = turnContext.config.currentTimeReminder else { return }
    let due = sess.state.currentTimeReminder.takeReminderDue(
        windowId: windowId,
        currentTime: now,
        intervalSeconds: config.intervalSeconds,
        afterUserOrToolOutput: config.deliveryMode == .afterUserOrToolOutput
    )
    guard due else { return }
    sess.recordConversationItems(
        turnContext,
        items: [CurrentTimeReminder(currentTime: now).asResponseItem()]
    )
}
