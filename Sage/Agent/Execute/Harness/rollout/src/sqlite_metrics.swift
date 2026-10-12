//
//  sqlite_metrics.swift
//  SageRollout
//
//  Port of codex-rs/rollout/src/sqlite_metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Bridges SageState DbTelemetry. otel originator tags wait for Phase 10.
//

import SageState
import Foundation

public func sqliteTelemetryRecorder() -> DbTelemetryHandle {
    NOOP_DB_TELEMETRY
}
