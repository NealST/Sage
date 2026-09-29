//
//  turn_timing.swift
//  CodexCore
//
//  Port of codex-rs/core/src/turn_timing.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//

import Foundation

public struct TurnTiming: Equatable, Sendable {
    public var startedAt: Date
    public var firstTokenAt: Date?
    public var completedAt: Date?

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    public var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    public mutating func markFirstToken() {
        if firstTokenAt == nil { firstTokenAt = Date() }
    }

    public mutating func complete() {
        completedAt = Date()
    }
}

public func nowUnixTimestampMs() -> Int64 {
    let millis = Date().timeIntervalSince1970 * 1000
    if millis >= Double(Int64.max) { return Int64.max }
    if millis <= Double(Int64.min) { return Int64.min }
    return Int64(millis)
}
