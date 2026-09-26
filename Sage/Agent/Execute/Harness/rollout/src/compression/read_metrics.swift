//
//  read_metrics.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/compression/read_metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  One observation per reader. Export waits for otel.
//

import Foundation

enum ReadFailureSource {
    case stream
    case readerBusy
    case taskJoin
}

struct ReadMetrics {
    var format: String = "unknown"
    var reachedEof = false
    var duration: TimeInterval = 0
    var readAnyLine = false
    var failureStage: String?

    mutating func failed(stage: String, source: ReadFailureSource, error: Error) {
        if failureStage == nil {
            failureStage = stage
            _ = (source, compressionErrorKind(error))
        }
    }
}
