//
//  current_time_reminder.swift
//  CodexCore
//
//  Port of codex-rs/core/src/context/current_time_reminder.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import CodexProtocol
import Foundation

public struct CurrentTimeReminder: ContextualUserFragment, Equatable, Sendable {
    public var currentTime: Date

    public init(currentTime: Date) {
        self.currentTime = currentTime
    }

    public func formattedTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: currentTime)
    }

    public var contentKind: ContentItemKind { ContentItemKind("current_time.reminder") }
    public var role: String { "developer" }
    public var openMarker: String { "<current_time_reminder>" }
    public var closeMarker: String { "</current_time_reminder>" }
    public var body: String { "It is \(formattedTime())." }
}

public struct CurrentTimeUnavailable: ContextualUserFragment, Equatable, Sendable {
    public static let message = "failed to read current time"

    public init() {}

    public var contentKind: ContentItemKind { ContentItemKind("current_time.unavailable") }
    public var role: String { "developer" }
    public var openMarker: String { "<current_time_unavailable>" }
    public var closeMarker: String { "</current_time_unavailable>" }
    public var body: String { Self.message }
}
