//
//  error_metrics.swift
//  CodexRollout
//
//  Port of codex-rs/rollout/src/compression/error_metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  otel counters are no-ops until the otel crate is ported.
//

import Foundation

enum FailureMetric {
    case file(RolloutCompressionTrigger)
    case materialize
    case run(RolloutCompressionTrigger)
    case scan(RolloutCompressionTrigger)
    case tempCleanup(RolloutCompressionTrigger)

    func record(stage: String, error: Error) {
        _ = (stage, compressionErrorKind(error), self)
    }
}

func compressionErrorKind(_ error: Error) -> String {
    let nsError = error as NSError
    switch nsError.code {
    case NSFileNoSuchFileError, Int(ENOENT): return "not_found"
    case NSFileWriteNoPermissionError, NSFileReadNoPermissionError, Int(EACCES):
        return "permission_denied"
    case NSFileWriteFileExistsError, Int(EEXIST): return "already_exists"
    default: return "other"
    }
}
