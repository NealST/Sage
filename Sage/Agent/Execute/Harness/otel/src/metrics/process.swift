//
//  process.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/process.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

import os

private let processStartRecorded = OSAllocatedUnfairLock(initialState: false)

/// Record the process start counter at most once for this process.
public func recordProcessStartOnce(_ metrics: MetricsClient, originator: String) throws -> Bool {
    let first = processStartRecorded.withLock { recorded -> Bool in
        if recorded { return false }
        recorded = true
        return true
    }
    guard first else { return false }
    try metrics.counter(
        PROCESS_START_METRIC,
        inc: 1,
        tags: [(ORIGINATOR_TAG, boundedOriginatorTagValue(originator))]
    )
    return true
}
