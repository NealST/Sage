//
//  ScheduleNotifier.swift
//  Sage
//

import Foundation
import UserNotifications

/// Payload stashed on a schedule notification so a tap can reopen the run.
nonisolated struct ScheduleNotificationPayload: Sendable, Equatable {
    var scheduleID: UUID
    var title: String
    var body: String
    var kind: ScheduleKind
    var projectID: UUID?
    var taskID: UUID?

    fileprivate enum Key {
        static let scheduleID = "scheduleID"
        static let kind = "kind"
        static let projectID = "projectID"
        static let taskID = "taskID"
        static let isSchedule = "sage.schedule"
    }

    var userInfo: [String: String] {
        var info: [String: String] = [
            Key.isSchedule: "1",
            Key.scheduleID: scheduleID.uuidString,
            Key.kind: kind.rawValue,
        ]
        if let projectID {
            info[Key.projectID] = projectID.uuidString
        }
        if let taskID {
            info[Key.taskID] = taskID.uuidString
        }
        return info
    }

    static func fromUserInfo(_ userInfo: [AnyHashable: Any]) -> ScheduleNotificationPayload? {
        guard userInfo[Key.isSchedule] as? String == "1",
              let rawID = userInfo[Key.scheduleID] as? String,
              let scheduleID = UUID(uuidString: rawID),
              let rawKind = userInfo[Key.kind] as? String,
              let kind = ScheduleKind(rawValue: rawKind)
        else { return nil }
        let projectID = (userInfo[Key.projectID] as? String).flatMap(UUID.init(uuidString:))
        let taskID = (userInfo[Key.taskID] as? String).flatMap(UUID.init(uuidString:))
        return ScheduleNotificationPayload(
            scheduleID: scheduleID,
            title: "",
            body: "",
            kind: kind,
            projectID: projectID,
            taskID: taskID
        )
    }
}

enum ScheduleNotifier {
    /// Asks for notification permission. Safe to call from Save, before the first fire.
    static func requestAuthorization() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    /// Posts a completion or failure notification. Taps are handled by `AppDelegate`.
    static func post(_ payload: ScheduleNotificationPayload) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            case .denied:
                return
            default:
                break
            }
            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.body
            content.sound = .default
            content.userInfo = payload.userInfo as [AnyHashable: Any]
            let request = UNNotificationRequest(
                identifier: "sage.schedule.\(payload.scheduleID.uuidString).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
