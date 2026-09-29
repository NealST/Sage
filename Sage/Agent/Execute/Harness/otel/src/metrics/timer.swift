//
//  timer.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/timer.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `Drop` records via `deinit`. Uses ContinuousClock instead of Instant.
//

import Foundation
import os

public final class Timer: @unchecked Sendable {
    private let name: String
    private let tags: [(String, String)]
    private let client: MetricsClient
    private let start: ContinuousClock.Instant
    private let lock = OSAllocatedUnfairLock(initialState: false)

    init(name: String, tags: [(String, String)], client: MetricsClient) {
        self.name = name
        self.tags = tags
        self.client = client
        self.start = ContinuousClock.now
    }

    deinit {
        let already = lock.withLock { recorded -> Bool in
            if recorded { return true }
            recorded = true
            return false
        }
        if !already {
            try? record([])
        }
    }

    public func record(_ additionalTags: [(String, String)] = []) throws {
        var combined = additionalTags
        combined.append(contentsOf: tags)
        let elapsed = ContinuousClock.now - start
        try client.recordDuration(name, duration: elapsed, tags: combined)
    }
}
