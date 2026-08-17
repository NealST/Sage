//
//  ScheduleClock.swift
//  Sage
//
//  Wall-clock next-fire + slash cadence parsing.
//

import Foundation

nonisolated enum ScheduleClock {
    /// Next fire at or after `from` (typically `.now`).
    static func nextFireDate(for cadence: ScheduleCadence, after from: Date = .now) -> Date? {
        let calendar = Calendar.current
        switch cadence {
        case .once(let date):
            return date > from ? date : nil
        case .delay(let seconds):
            return from.addingTimeInterval(max(1, seconds))
        case .interval(let seconds):
            let step = max(60, seconds)
            return from.addingTimeInterval(step)
        case .weekdays(let hour, let minute):
            return nextMatching(
                after: from,
                hour: hour,
                minute: minute,
                calendar: calendar
            ) { weekday in
                (2...6).contains(weekday)
            }
        case .daily(let hour, let minute):
            return nextMatching(
                after: from,
                hour: hour,
                minute: minute,
                calendar: calendar
            ) { _ in true }
        }
    }

    /// After a successful run: once-jobs go nil (caller should disable).
    static func nextFireDateAfterRun(for cadence: ScheduleCadence, from now: Date = .now) -> Date? {
        switch cadence {
        case .once, .delay:
            return nil
        case .interval, .weekdays, .daily:
            return nextFireDate(for: cadence, after: now)
        }
    }

    private static func nextMatching(
        after from: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar,
        weekdayAllowed: (Int) -> Bool
    ) -> Date? {
        var cursor = from
        let match = DateComponents(hour: hour, minute: minute, second: 0)
        for _ in 0..<14 {
            guard let candidate = calendar.nextDate(
                after: cursor,
                matching: match,
                matchingPolicy: .nextTime
            ) else { return nil }
            let weekday = calendar.component(.weekday, from: candidate)
            if weekdayAllowed(weekday) { return candidate }
            cursor = candidate
        }
        return nil
    }
}

nonisolated enum ScheduleCadenceParser {
    struct Preset: Identifiable, Equatable, Sendable {
        var id: String { insert }
        let insert: String
        let description: String
    }

    static let presets: [Preset] = [
        Preset(insert: "weekdays 9:00", description: "Monday–Friday at 9:00"),
        Preset(insert: "every morning", description: "Every day at 9:00"),
        Preset(insert: "daily", description: "Every day at 9:00"),
        Preset(insert: "in 1 hour", description: "Once, an hour from now"),
    ]

    /// Parse `/schedule` argument into cadence + remaining prompt (prompt may be empty).
    static func parseCadenceAndPrompt(
        _ argument: String
    ) -> (cadence: ScheduleCadence, prompt: String)? {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let (cadence, rest) = parseOnceIn(trimmed) {
            return (cadence, rest.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let (cadence, rest) = parseWeekdays(trimmed) {
            return (cadence, rest.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if trimmed.lowercased().hasPrefix("every morning") {
            let rest = String(trimmed.dropFirst("every morning".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.daily(hour: 9, minute: 0), rest)
        }
        if trimmed.lowercased().hasPrefix("daily") {
            let after = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let (time, rest) = parseLeadingClock(after) {
                return (.daily(hour: time.hour, minute: time.minute), rest)
            }
            return (.daily(hour: 9, minute: 0), after)
        }
        return nil
    }

    /// Parse `/schedule` argument into cadence + remaining prompt.
    static func parseAgentArgument(_ argument: String) -> (cadence: ScheduleCadence, prompt: String)? {
        guard let parsed = parseCadenceAndPrompt(argument), !parsed.prompt.isEmpty else {
            return nil
        }
        return parsed
    }

    /// Cadence for a slash preset, evaluated at save time (`in 1 hour` is relative).
    static func cadence(fromPresetInsert insert: String, now: Date = .now) -> ScheduleCadence? {
        if insert.lowercased() == "in 1 hour" {
            return .once(date: now.addingTimeInterval(3600))
        }
        return parseAgentArgument("\(insert) _")?.cadence
    }

    /// Completions while the user is still typing `/schedule …` (no prompt yet).
    static func autocompleteInserts(forDraft draft: String) -> [Preset] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/schedule") else { return [] }
        let afterCommand = String(trimmed.dropFirst("/schedule".count))
        if afterCommand.isEmpty || afterCommand == " " {
            return presets
        }
        guard afterCommand.hasPrefix(" ") else { return [] }
        let arg = afterCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if parseAgentArgument(arg) != nil { return [] }
        let lowered = arg.lowercased()
        return presets.filter { $0.insert.hasPrefix(lowered) || lowered.hasPrefix($0.insert) }
            .filter { parseAgentArgument($0.insert + " x") != nil }
    }

    private static func parseOnceIn(_ raw: String) -> (ScheduleCadence, String)? {
        let lowered = raw.lowercased()
        guard lowered.hasPrefix("in ") else { return nil }
        let rest = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let amount = Double(parts[0]) else { return nil }
        let unit = parts[1].lowercased()
        let seconds: TimeInterval
        if unit.hasPrefix("hour") {
            seconds = amount * 3600
        } else if unit.hasPrefix("min") {
            seconds = amount * 60
        } else {
            return nil
        }
        let prompt: String
        if parts.count == 3 {
            prompt = String(parts[2])
        } else if parts.count == 2 {
            prompt = ""
        } else {
            return nil
        }
        return (.delay(seconds: seconds), prompt)
    }

    private static func parseWeekdays(_ raw: String) -> (ScheduleCadence, String)? {
        let lowered = raw.lowercased()
        guard lowered.hasPrefix("weekdays") else { return nil }
        let after = String(raw.dropFirst("weekdays".count))
            .trimmingCharacters(in: .whitespaces)
        if let (time, rest) = parseLeadingClock(after) {
            return (.weekdays(hour: time.hour, minute: time.minute), rest)
        }
        return (.weekdays(hour: 9, minute: 0), after)
    }

    private static func parseLeadingClock(
        _ raw: String
    ) -> ((hour: Int, minute: Int), String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let token = String(trimmed.prefix { !$0.isWhitespace })
        let rest = String(trimmed.dropFirst(token.count))
            .trimmingCharacters(in: .whitespaces)
        if let time = parseClock(token) {
            return (time, rest)
        }
        return nil
    }

    private static func parseClock(_ raw: String) -> (hour: Int, minute: Int)? {
        var token = raw.lowercased()
        var hourAdjust = 0
        if token.hasSuffix("am") {
            token = String(token.dropLast(2))
        } else if token.hasSuffix("pm") {
            token = String(token.dropLast(2))
            hourAdjust = 12
        }
        let parts = token.split(separator: ":")
        guard let hourPart = parts.first, let hour = Int(hourPart) else { return nil }
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        var resolved = hour
        if hourAdjust == 12 {
            if hour < 12 { resolved = hour + 12 }
        } else if hour == 12, raw.lowercased().contains("am") {
            resolved = 0
        }
        guard (0...23).contains(resolved), (0...59).contains(minute) else { return nil }
        return (resolved, minute)
    }
}
