//
//  backoff.swift
//  CodexAsyncUtils
//
//  Port of codex-rs/async-utils/src/backoff.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  `rand::rng().random_range(0.9..1.1)` maps to `Double.random(in: 0.9..<1.1)`
//  (both half-open). `Duration::from_millis` maps to Swift `Duration`.
//

import Foundation

private let initialDelayMs: Double = 200
private let backoffFactor: Double = 2.0

/// Return a retry delay starting at 200 ms and doubling on each subsequent
/// attempt, with up to 10% jitter. Attempts zero and one both use the
/// initial delay.
public func backoff(attempt: UInt64) -> Duration {
    let exp = pow(backoffFactor, Double(attempt > 0 ? attempt - 1 : 0))
    // Upstream truncates the base to whole milliseconds before jitter.
    let base = UInt64(initialDelayMs * exp)
    let jitter = Double.random(in: 0.9 ..< 1.1)
    return .milliseconds(Int(Double(base) * jitter))
}
