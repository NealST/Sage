//
//  metrics.swift
//  CodexCore
//
//  Port of codex-rs/core/src/plugins/metrics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Sidecar creation closes over Session, TurnContext, analytics, and the
//  plugin-metrics extension.
//

import CodexProtocol
import Foundation

public func sidecarForCommand() async throws -> Never {
    throw CodexErr.unsupportedOperation(
        "sidecar_for_command waits on Session / TurnContext / PluginMetricsSidecar"
    )
}

public func finishAndTrackMeasurements() async throws {
    throw CodexErr.unsupportedOperation(
        "finish_and_track_measurements waits on Session / analytics_events_client"
    )
}
