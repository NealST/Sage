//
//  util.swift
//  Sage
//
//  Port of codex-rs/core/src/util.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Core utility functions. The `feedback_tags!` macro is adapted to use
//  `os.Logger` (there is no tracing layer → feedback tag capture in Sage).
//  `error_or_panic` maps to `assertionFailure` in debug / `os_log .error`
//  in release. `normalize_thread_name` is faithful.
//

import Foundation
import os.log

private let harnessLogger = Logger(subsystem: "com.sage.harness", category: "util")

/// Emit structured feedback metadata as key/value pairs.
///
/// Sage adaptation: logs to os.Logger instead of tracing event. Sage does not
/// have the codex_feedback metadata layer; these tags are observable in Console.
public func feedbackTags(_ tags: [String: String]) {
    let formatted = tags.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    harnessLogger.info("feedback_tags: \(formatted, privacy: .public)")
}

public func emitFeedbackAuthRecoveryTags(
    authRecoveryMode: String,
    authRecoveryPhase: String,
    authRecoveryOutcome: String,
    authRequestId: String? = nil,
    authCfRay: String? = nil,
    authError: String? = nil,
    authErrorCode: String? = nil
) {
    feedbackTags([
        "auth_recovery_mode": authRecoveryMode,
        "auth_recovery_phase": authRecoveryPhase,
        "auth_recovery_outcome": authRecoveryOutcome,
        "auth_401_request_id": authRequestId ?? "",
        "auth_401_cf_ray": authCfRay ?? "",
        "auth_401_error": authError ?? "",
        "auth_401_error_code": authErrorCode ?? "",
    ])
}

/// In debug builds, triggers `assertionFailure`; in release, logs an error.
/// Maps to upstream `error_or_panic`.
public func errorOrPanic(_ message: @autoclosure () -> String) {
    let msg = message()
    #if DEBUG
    assertionFailure(msg)
    #else
    harnessLogger.error("\(msg, privacy: .public)")
    #endif
}

/// Trim a thread name and return `nil` if it is empty after trimming.
public func normalizeThreadName(_ name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
