//
//  otel_init.swift
//  CodexCore
//
//  Port of codex-rs/core/src/otel_init.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `Config` lives in the Sage app module, so callers pass OtelInitInputs
//  scalars. HttpClientFactory / Feature flags are omitted. Metrics install
//  uses CodexOtel's in-memory provider (plan §Phase 10).
//

import CodexOtel
import CodexRollout
import CodexState
import Foundation

public struct OtelInitInputs: Sendable {
    public var environment: String
    public var serviceName: String
    public var serviceVersion: String
    public var codexHome: String
    public var exporter: OtelExporter
    public var traceExporter: OtelExporter
    public var metricsExporter: OtelExporter
    public var analyticsEnabled: Bool
    public var runtimeMetrics: Bool
    public var spanAttributes: [String: String]
    public var tracestate: [String: [String: String]]

    public init(
        environment: String,
        serviceName: String,
        serviceVersion: String,
        codexHome: String,
        exporter: OtelExporter = .none,
        traceExporter: OtelExporter = .none,
        metricsExporter: OtelExporter = .none,
        analyticsEnabled: Bool = false,
        runtimeMetrics: Bool = false,
        spanAttributes: [String: String] = [:],
        tracestate: [String: [String: String]] = [:]
    ) {
        self.environment = environment
        self.serviceName = serviceName
        self.serviceVersion = serviceVersion
        self.codexHome = codexHome
        self.exporter = exporter
        self.traceExporter = traceExporter
        self.metricsExporter = metricsExporter
        self.analyticsEnabled = analyticsEnabled
        self.runtimeMetrics = runtimeMetrics
        self.spanAttributes = spanAttributes
        self.tracestate = tracestate
    }
}

/// Build an OpenTelemetry provider from app settings.
///
/// Returns `nil` when OTEL export is disabled.
public func buildProvider(_ inputs: OtelInitInputs) throws -> OtelProvider? {
    let metricsExporter = inputs.analyticsEnabled ? inputs.metricsExporter : .none
    return try OtelProvider.tryNew(
        OtelSettings(
            environment: inputs.environment,
            serviceName: inputs.serviceName,
            serviceVersion: inputs.serviceVersion,
            codexHome: inputs.codexHome,
            exporter: inputs.exporter,
            traceExporter: inputs.traceExporter,
            metricsExporter: metricsExporter,
            runtimeMetrics: inputs.runtimeMetrics,
            spanAttributes: inputs.spanAttributes,
            tracestate: inputs.tracestate
        )
    )
}

public func recordProcessStart(_ otel: OtelProvider?, originator: String) {
    guard let metrics = otel?.metrics() else { return }
    _ = try? recordProcessStartOnce(metrics, originator: originator)
}

public func installSqliteTelemetry(_ otel: OtelProvider?, originator: String) {
    guard otel?.metrics() != nil else { return }
    _ = originator
    _ = installProcessDbTelemetry(sqliteTelemetryRecorder())
}
