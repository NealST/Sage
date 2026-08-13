//
//  ReminderTools.swift
//  Sage
//

import EventKit
import Foundation

// MARK: - Reminders

struct CreateReminderTool: AgentTool {
    let definition = ToolDefinition(
        name: "create_reminder",
        description: """
            Create a reminder in the macOS Reminders app via EventKit. \
            Requires Reminders permission — will prompt on first use. \
            Optionally set a due date (ISO 8601 format: "2024-12-31T09:00:00"). \
            The reminder is added to the user's default reminder list.
            """,
        parameters: .schemaObject(
            properties: [
                "title": .stringProperty("Reminder title (required)"),
                "notes": .stringProperty("Optional notes/body text for the reminder"),
                "due_date": .stringProperty("Optional due date in ISO 8601 format (e.g. '2024-12-31T09:00:00'). Omit for no due date."),
                "priority": .intProperty("Priority: 0 = none (default), 1 = high, 5 = medium, 9 = low"),
            ],
            required: ["title"]
        )
    )

    private struct Args: Decodable {
        let title: String
        let notes: String?
        let dueDate: String?
        let priority: Int?
    }

    private static let store = EKEventStore()

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)

        guard !args.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.invalidArguments("Reminder title cannot be empty.")
        }

        let store = Self.store

        // Request access
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }

        guard granted else {
            throw ToolError.operationFailed(
                "Reminders permission denied. Enable in System Settings → Privacy & Security → Reminders → Sage."
            )
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = args.title
        reminder.notes = args.notes
        reminder.priority = args.priority ?? 0
        reminder.calendar = store.defaultCalendarForNewReminders()

        // Parse due date if provided
        if let dueDateStr = args.dueDate, !dueDateStr.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            // Try with fractional seconds first, then without
            var date = formatter.date(from: dueDateStr)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: dueDateStr)
            }
            if date == nil {
                // Try basic format without timezone: "2024-12-31T09:00:00"
                let basic = ISO8601DateFormatter()
                basic.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
                date = basic.date(from: dueDateStr)
            }

            guard let parsedDate = date else {
                throw ToolError.invalidArguments(
                    "Invalid due_date format: '\(dueDateStr)'. Use ISO 8601 (e.g. '2024-12-31T09:00:00' or '2024-12-31T09:00:00Z')."
                )
            }

            let calendar = Calendar.current
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: parsedDate
            )
            reminder.dueDateComponents = components
        }

        try store.save(reminder, commit: true)

        var result = "[OK] Reminder created: \"\(args.title)\""
        if let dueDate = args.dueDate {
            result += " (due: \(dueDate))"
        }
        return result
    }
}

