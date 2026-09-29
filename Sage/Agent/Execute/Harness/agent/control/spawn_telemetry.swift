//
//  spawn_telemetry.swift
//  CodexCore
//
//  Port of codex-rs/core/src/agent/control/spawn_telemetry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Phase timings are recorded in-memory. SessionTelemetry / otel emission
//  waits on Phase 10.
//

import CodexProtocol
import Foundation

public struct SpawnMeasurements: Equatable, Sendable {
    public var historyMode: ThreadHistoryMode
    public var residencyReservation: Duration?
    public var forkContext: Duration?
    public var childCreate: Duration
    public var durabilityWait: Duration
    public var inputAdmission: Duration
    public var total: Duration

    public init(
        historyMode: ThreadHistoryMode,
        residencyReservation: Duration? = nil,
        forkContext: Duration? = nil,
        childCreate: Duration,
        durabilityWait: Duration,
        inputAdmission: Duration,
        total: Duration
    ) {
        self.historyMode = historyMode
        self.residencyReservation = residencyReservation
        self.forkContext = forkContext
        self.childCreate = childCreate
        self.durabilityWait = durabilityWait
        self.inputAdmission = inputAdmission
        self.total = total
    }
}

public struct SpawnTelemetryRecord: Equatable, Sendable {
    public var phase: String
    public var duration: Duration
    public var forkMode: String
    public var historyMode: String
    public var multiAgentVersion: String
}

public func recordSpawnSuccess(
    forkMode: SpawnAgentForkMode?,
    multiAgentVersion: MultiAgentVersion,
    measurements: SpawnMeasurements
) -> [SpawnTelemetryRecord] {
    let forkModeLabel: String
    switch forkMode {
    case .none: forkModeLabel = "none"
    case .fullHistory: forkModeLabel = "all"
    case .lastNTurns: forkModeLabel = "last_n"
    }
    let historyMode: String
    switch measurements.historyMode {
    case .legacy: historyMode = "legacy"
    case .paginated: historyMode = "paginated"
    }
    let version: String
    switch multiAgentVersion {
    case .disabled: version = "disabled"
    case .v1: version = "v1"
    case .v2: version = "v2"
    }
    var records: [SpawnTelemetryRecord] = []
    let record: (String, Duration) -> Void = { phase, duration in
        records.append(
            SpawnTelemetryRecord(
                phase: phase,
                duration: duration,
                forkMode: forkModeLabel,
                historyMode: historyMode,
                multiAgentVersion: version
            )
        )
    }
    if let duration = measurements.residencyReservation {
        record("residency_reservation", duration)
    }
    if let duration = measurements.forkContext {
        record("fork_context", duration)
    }
    record("child_create", measurements.childCreate)
    record("durability_wait", measurements.durabilityWait)
    record("input_admission", measurements.inputAdmission)
    record("total", measurements.total)
    return records
}
