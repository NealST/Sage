//
//  client.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/client.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  In-memory instruments only (plan §Phase 10). No OpenTelemetry SDK /
//  OTLP export. Snapshot returns recorded observations instead of
//  ResourceMetrics. Duration uses Swift Duration.
//

import CodexUtils
import Foundation
import os

let millisecondDurationUnit = "ms"
let millisecondDurationDescription = "Duration in milliseconds."
let millisecondDurationBoundaries: [Double] = [
    0, 5, 10, 25, 50, 75, 100, 250, 500, 750, 1_000, 1_250, 1_500,
    1_750, 2_000, 2_250, 2_500, 3_000, 3_500, 4_000, 4_500, 5_000, 6_000,
    7_000, 7_500, 8_000, 9_000, 10_000, 12_000, 15_000, 20_000, 30_000, 60_000,
    120_000,
]
let secondDurationUnit = "s"
let secondDurationBoundaries: [Double] = [
    0, 0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0,
    7.5, 10.0, 12.0, 15.0, 20.0, 30.0, 60.0, 120.0,
]

public enum MetricKind: String, Equatable, Sendable {
    case counter
    case histogram
    case gauge
    case duration
}

public struct MetricObservation: Equatable, Sendable {
    public var kind: MetricKind
    public var name: String
    public var value: Double
    public var tags: [(String, String)]
    public var unit: String?

    public static func == (lhs: MetricObservation, rhs: MetricObservation) -> Bool {
        lhs.kind == rhs.kind
            && lhs.name == rhs.name
            && lhs.value == rhs.value
            && lhs.tags.elementsEqual(rhs.tags, by: ==)
            && lhs.unit == rhs.unit
    }
}

final class MetricsClientInner: @unchecked Sendable {
    let identity = UUID()
    var networkPolicyIsManaged = false
    let statsigDisabledMetrics: [String]
    let defaultTags: [String: String]
    let runtimeReader: Bool
    private let lock = OSAllocatedUnfairLock(initialState: [MetricObservation]())

    init(config: MetricsConfig) {
        statsigDisabledMetrics = config.statsigDisabledMetrics
        defaultTags = config.defaultTags
        runtimeReader = config.runtimeReader
    }

    func record(
        kind: MetricKind,
        name: String,
        value: Double,
        tags: [(String, String)],
        unit: String? = nil
    ) throws {
        try validateMetricName(name)
        if kind == .counter, value < 0 {
            throw MetricsError.negativeCounterIncrement(name: name, inc: Int64(value))
        }
        if statsigDisabledMetrics.contains(name) {
            return
        }
        var merged = defaultTags.map { ($0.key, $0.value) }
        merged.append(contentsOf: tags)
        try validateObservationTags(merged)
        lock.withLock { observations in
            observations.append(
                MetricObservation(kind: kind, name: name, value: value, tags: merged, unit: unit)
            )
        }
    }

    func snapshot() -> [MetricObservation] {
        lock.withLock { $0 }
    }

    func clear() {
        lock.withLock { $0.removeAll() }
    }
}

private func validateObservationTags(_ tags: [(String, String)]) throws {
    for (key, value) in tags {
        try validateTagKey(key)
        try validateTagValue(value)
    }
}

/// OpenTelemetry metrics client used by Codex.
public final class MetricsClient: @unchecked Sendable {
    let inner: MetricsClientInner
    private let active: OSAllocatedUnfairLock<MetricsClientInner>?

    public init(_ config: MetricsConfig) throws {
        try validateTags(config.defaultTags)
        if case .otlp(.none) = config.exporter {
            throw MetricsError.exporterDisabled
        }
        inner = MetricsClientInner(config: config)
        active = nil
    }

    init(inner: MetricsClientInner, active: OSAllocatedUnfairLock<MetricsClientInner>?) {
        self.inner = inner
        self.active = active
    }

    func withActiveSlot(_ slot: OSAllocatedUnfairLock<MetricsClientInner>) -> MetricsClient {
        MetricsClient(inner: inner, active: slot)
    }

    func activeInner() -> MetricsClientInner {
        if let active {
            return active.withLock { $0 }
        }
        return inner
    }

    public func counter(_ name: String, inc: Int64, tags: [(String, String)] = []) throws {
        try activeInner().record(kind: .counter, name: name, value: Double(inc), tags: tags)
    }

    public func counterWithDescription(
        _ name: String,
        description: String,
        inc: Int64,
        tags: [(String, String)] = []
    ) throws {
        _ = description
        try counter(name, inc: inc, tags: tags)
    }

    public func histogram(_ name: String, value: Int64, tags: [(String, String)] = []) throws {
        try activeInner().record(kind: .histogram, name: name, value: Double(value), tags: tags)
    }

    public func histogramWithBoundaries(
        _ name: String,
        value: Int64,
        boundaries: [Double],
        tags: [(String, String)] = []
    ) throws {
        _ = boundaries
        try histogram(name, value: value, tags: tags)
    }

    public func gauge(_ name: String, value: Int64, tags: [(String, String)] = []) throws {
        try activeInner().record(kind: .gauge, name: name, value: Double(value), tags: tags)
    }

    public func gaugeWithDescription(
        _ name: String,
        description: String,
        value: Int64,
        tags: [(String, String)] = []
    ) throws {
        _ = description
        try gauge(name, value: value, tags: tags)
    }

    public func registerObservableGaugeWithDescription(
        _ name: String,
        description: String,
        observe: @escaping @Sendable () -> Int64,
        tags: [(String, String)] = []
    ) throws {
        try gaugeWithDescription(name, description: description, value: observe(), tags: tags)
    }

    public func recordDuration(
        _ name: String,
        duration: Duration,
        tags: [(String, String)] = []
    ) throws {
        let ms = duration.milliseconds
        try activeInner().record(
            kind: .duration,
            name: name,
            value: ms,
            tags: tags,
            unit: millisecondDurationUnit
        )
    }

    func recordDurationMsF64(
        _ name: String,
        durationMs: Double,
        tags: [(String, String)] = []
    ) throws {
        try activeInner().record(
            kind: .duration,
            name: name,
            value: durationMs,
            tags: tags,
            unit: millisecondDurationUnit
        )
    }

    public func recordDurationSecondsWithDescription(
        _ name: String,
        description: String,
        duration: Duration,
        tags: [(String, String)] = []
    ) throws {
        _ = description
        try activeInner().record(
            kind: .duration,
            name: name,
            value: duration.seconds,
            tags: tags,
            unit: secondDurationUnit
        )
    }

    public func startTimer(_ name: String, tags: [(String, String)] = []) -> Timer {
        Timer(name: name, tags: tags, client: self)
    }

    public func snapshot() throws -> [MetricObservation] {
        let inner = activeInner()
        guard inner.runtimeReader else {
            throw MetricsError.runtimeSnapshotUnavailable
        }
        return inner.snapshot()
    }

    public func shutdown() throws {
        bufferedMetricsGlobal.suspend(self)
        inner.clear()
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }

    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
