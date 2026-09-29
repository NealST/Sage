//
//  provider.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/provider.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  try_new / shutdown / metrics() keep the same gate. Logger and tracer
//  providers are omitted (no OpenTelemetry SDK). Metrics use the
//  in-memory client. Tracing filter helpers stay for target names.
//

import Foundation
import os

public final class OtelProvider: @unchecked Sendable {
    public var metricsClient: MetricsClient?
    private let shutdownStarted = OSAllocatedUnfairLock(initialState: false)

    public static func tryNew(_ settings: OtelSettings) throws -> OtelProvider? {
        let logEnabled = !isNone(settings.exporter)
        let traceEnabled = !isNone(settings.traceExporter)
        let metricExporter = resolveExporter(settings.metricsExporter)
        let metricsEnabled = !isNone(metricExporter)

        if !logEnabled && !traceEnabled && !metricsEnabled {
            try setTracestateEntries([:])
            bufferedMetricsGlobal.disable()
            return nil
        }

        if traceEnabled {
            try validateSpanAttributes(settings.spanAttributes)
        }
        try validateTracestateEntries(settings.tracestate)

        let metrics: MetricsClient?
        if isNone(metricExporter) {
            metrics = nil
        } else {
            var config = MetricsConfig.otlp(
                environment: settings.environment,
                serviceName: settings.serviceName,
                serviceVersion: settings.serviceVersion,
                exporter: settings.metricsExporter
            )
            config.exporter = .inMemory
            if settings.runtimeMetrics {
                config = config.withRuntimeReader()
            }
            metrics = try MetricsClient(config)
        }

        try setTracestateEntries(settings.tracestate)
        let provider = OtelProvider()
        if var metrics {
            metrics = installGlobal(metrics)
            provider.metricsClient = metrics
            if case .statsig = settings.metricsExporter {
                installGlobalStatsigSettings(
                    StatsigMetricsSettings(environment: settings.environment)
                )
            }
        } else {
            bufferedMetricsGlobal.disable()
        }
        return provider
    }

    public func shutdown() {
        let first = shutdownStarted.withLock { started -> Bool in
            if started { return false }
            started = true
            return true
        }
        guard first else { return }
        try? metricsClient?.shutdown()
    }

    public func metrics() -> MetricsClient? {
        metricsClient
    }

    public static func logExportFilter(target: String) -> Bool {
        isLogExportTarget(target)
    }

    public static func traceExportFilter(target: String, isSpan: Bool) -> Bool {
        if isSpan {
            return target != "h2" && !target.hasPrefix("h2::")
        }
        return isTraceSafeTarget(target)
    }

    public static func codexExportFilter(target: String) -> Bool {
        logExportFilter(target: target)
    }

    deinit {
        shutdown()
    }
}

private func isNone(_ exporter: OtelExporter) -> Bool {
    if case .none = exporter { return true }
    return false
}
