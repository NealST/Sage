//
//  TaskCompletionNotifier.swift
//  Sage
//
//  Completion/failure banners for interactive (window-started) tasks, plus
//  the "waiting on you" attention banner for pending decisions. Schedule-
//  owned tasks are excluded by the caller — the schedule path already posts
//  with its own cadence and mute settings.
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

/// A pending decision while the owning window is unwatched. Only carries a
/// reveal action — the Allow/Skip decision itself is made in the transcript
/// on unclipped arguments, never inline in a banner.
nonisolated struct ApprovalAttentionPayload: Sendable, Equatable {
    /// `nil` = the General session.
    var projectID: UUID?
    var title: String
    var body: String

    fileprivate enum Key {
        static let isApproval = "sage.approval"
        static let projectID = "projectID"
    }

    var userInfo: [String: String] {
        var info: [String: String] = [Key.isApproval: "1"]
        if let projectID {
            info[Key.projectID] = projectID.uuidString
        }
        return info
    }

    /// Banner identity — one per session, so a second queued approval
    /// replaces the first instead of stacking.
    var notificationIdentifier: String {
        "sage.attention.\(projectID?.uuidString ?? "general")"
    }

    static func fromUserInfo(_ userInfo: [AnyHashable: Any]) -> Self? {
        guard userInfo[Key.isApproval] as? String == "1" else { return nil }
        let projectID = (userInfo[Key.projectID] as? String).flatMap(UUID.init(uuidString:))
        return Self(projectID: projectID, title: "", body: "")
    }
}

enum TaskCompletionNotifier {
    /// Banner categories — failure adds an inline Retry so the user can
    /// recover without the extra reveal-then-click round trip. The approval
    /// category is reveal-only; the decision stays in the transcript.
    enum CategoryID {
        static let completed = "sage.task.completed"
        static let failed = "sage.task.failed"
        static let approvalNeeded = "sage.attention.approval"
    }

    enum ActionID {
        static let open = "sage.task.open"
        static let retry = "sage.task.retry"
        static let review = "sage.attention.review"
    }

    /// Must run before the first `post` — categories attach actions to the
    /// banners, while the payload itself stays unchanged.
    static func registerCategories() {
        let open = UNNotificationAction(identifier: ActionID.open, title: "Open")
        let retry = UNNotificationAction(identifier: ActionID.retry, title: "Retry")
        let review = UNNotificationAction(identifier: ActionID.review, title: "Review")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: CategoryID.completed,
                actions: [open],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: CategoryID.failed,
                actions: [retry, open],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: CategoryID.approvalNeeded,
                actions: [review],
                intentIdentifiers: []
            ),
        ])
    }

    /// Posts the banner. Taps and inline actions are handled by `AppDelegate`.
    /// Skips silently when permission is denied — the Dock bounce still
    /// covers that case.
    static func post(
        _ payload: TaskNotificationPayload,
        playsSound: Bool,
        isFailure: Bool
    ) {
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
            // Failure is the signal the user is actively waiting on; completion
            // stays at active so a finished task never breaks through.
            content.interruptionLevel = isFailure ? .timeSensitive : .active
            content.categoryIdentifier = isFailure ? CategoryID.failed : CategoryID.completed
            content.userInfo = payload.userInfo as [AnyHashable: Any]
            let request = UNNotificationRequest(
                identifier: "sage.task.\(payload.taskID.uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    /// The deadlock case: the agent waits on the user while the user thinks
    /// Sage is working. No sound — the caller's Ping chime already fires on
    /// the same phase change; the banner adds the *visible* channel a Dock
    /// bounce can't reach (fullscreen, another Space, hidden Dock).
    static func postApprovalAttention(_ payload: ApprovalAttentionPayload) {
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
            // The agent is blocked on this; it should break through Focus.
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = CategoryID.approvalNeeded
            content.userInfo = payload.userInfo as [AnyHashable: Any]
            let request = UNNotificationRequest(
                identifier: payload.notificationIdentifier,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    /// Decision made (or the window took focus): retire the banner so it
    /// doesn't linger in Notification Center as a stale call to action.
    static func clearApprovalAttention(projectID: UUID?) {
        let identifier = ApprovalAttentionPayload(
            projectID: projectID,
            title: "",
            body: ""
        ).notificationIdentifier
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
