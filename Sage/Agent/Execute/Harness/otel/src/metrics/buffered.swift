//
//  buffered.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/buffered.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Mutex → OSAllocatedUnfairLock. Pair admission limits are faithful.
//

import Foundation
import os

private let maxPendingOperations = 256
private let maxMetadataBytes = 1024
private let maxTags = 16

private struct PendingOperation {
    var countName: String
    var durationName: String
    var duration: Duration
    var tags: [(String, String)]
}

private enum BufferedState {
    case startup([PendingOperation])
    case ready(MetricsClient)
    case disabled
}

final class BufferedMetrics: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: BufferedState.startup([]))

    func record(
        countName: String,
        durationName: String,
        duration: Duration,
        tags: [(String, String)]
    ) throws {
        let metadataBytes = tags.reduce(countName.utf8.count + durationName.utf8.count) {
            $0 + $1.0.utf8.count + $1.1.utf8.count
        }
        if tags.count > maxTags || metadataBytes > maxMetadataBytes {
            throw MetricsError.operationMetadataTooLarge
        }
        for name in [countName, durationName] {
            try validateMetricName(name)
            if name.utf8.count > 255 || name.first.map({ $0.isASCII && $0.isLetter }) != true {
                throw MetricsError.invalidMetricName(name: name)
            }
        }
        for (key, value) in tags {
            try validateTagKey(key)
            try validateTagValue(value)
        }
        try lock.withLock { state in
            switch state {
            case .startup(var pending):
                if pending.count < maxPendingOperations {
                    pending.append(
                        PendingOperation(
                            countName: countName,
                            durationName: durationName,
                            duration: duration,
                            tags: tags
                        )
                    )
                    state = .startup(pending)
                }
            case .ready(let metrics):
                try recordPair(metrics, countName, durationName, duration, tags)
            case .disabled:
                break
            }
        }
    }

    func enable(_ metrics: MetricsClient) {
        lock.withLock { state in
            let bound = MetricsClient(inner: metrics.inner, active: nil)
            if case .startup(let pending) = state {
                for operation in pending {
                    try? recordPair(
                        bound,
                        operation.countName,
                        operation.durationName,
                        operation.duration,
                        operation.tags
                    )
                }
            }
            state = .ready(bound)
        }
    }

    func disable() {
        lock.withLock { $0 = .disabled }
    }

    func suspend(_ metrics: MetricsClient) {
        lock.withLock { state in
            if case .ready(let current) = state,
               current.inner.identity == metrics.inner.identity {
                state = .startup([])
            }
        }
    }
}

private func recordPair(
    _ metrics: MetricsClient,
    _ countName: String,
    _ durationName: String,
    _ duration: Duration,
    _ tags: [(String, String)]
) throws {
    try metrics.counter(countName, inc: 1, tags: tags)
    try metrics.recordDuration(durationName, duration: duration, tags: tags)
}

let bufferedMetricsGlobal = BufferedMetrics()

/// Records one operation count and its duration in milliseconds through `MetricsClient`.
public func recordGlobalOperation(
    countName: String,
    durationName: String,
    duration: Duration,
    tags: [(String, String)] = []
) throws {
    try bufferedMetricsGlobal.record(
        countName: countName,
        durationName: durationName,
        duration: duration,
        tags: tags
    )
}
