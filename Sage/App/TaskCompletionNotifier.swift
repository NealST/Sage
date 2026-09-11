//
//  TaskCompletionNotifier.swift
//  Sage
//
//  Completion/failure banners for interactive (window-started) tasks.
//  Schedule-owned tasks are excluded by the caller — the schedule path
//  already posts with its own cadence and mute settings.
//

import Foundation
import UserNotifications

/// Payload stashed on an interactive task notification so a tap reopens
/// the task. Distinct marker from `ScheduleNotificationPayload`.
nonisolated struct TaskNotificationPayload: Sendable, Equatable {
    var projectID: UUID?
    var taskID: UUID
    var title: String
    var body: String

    fileprivate enum Key {
        static let isTask = "sage.task"
        static let projectID = "projectID"
        static let taskID = "taskID"
    }

    var userInfo: [String: String] {
        var info: [String: String] = [
            Key.isTask: "1",
            Key.taskID: taskID.uuidString,
        ]
        if let projectID {
            info[Key.projectID] = projectID.uuidString
        }
        return info
    }

    static func fromUserInfo(_ userInfo: [AnyHashable: Any]) -> Self? {
        guard userInfo[Key.isTask] as? String == "1",
              let rawID = userInfo[Key.taskID] as? String,
              let taskID = UUID(uuidString: rawID)
        else { return nil }
        let projectID = (userInfo[Key.projectID] as? String).flatMap(UUID.init(uuidString:))
        return Self(projectID: projectID, taskID: taskID, title: "", body: "")
    }
}

enum TaskCompletionNotifier {
    /// Posts the banner. Taps are handled by `AppDelegate`. Skips silently
    /// when permission is denied — the Dock bounce still covers that case.
    static func post(_ payload: TaskNotificationPayload, playsSound: Bool) {
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
            content.sound = playsSound ? .default : nil
            content.userInfo = payload.userInfo as [AnyHashable: Any]
            let request = UNNotificationRequest(
                identifier: "sage.task.\(payload.taskID.uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
