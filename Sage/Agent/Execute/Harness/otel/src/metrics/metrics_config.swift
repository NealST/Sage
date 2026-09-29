//
//  metrics_config.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  R4a: basename collides with otel/src/config.swift. HttpClientFactory
//  omitted. In-memory is the only live exporter.
//

import Foundation

let conversationTurnCountMetric = "codex.conversation.turn.count"

let statsigDisabledMetrics: [String] = [
    API_CALL_COUNT_METRIC,
    API_CALL_DURATION_METRIC,
    conversationTurnCountMetric,
    EXEC_SERVER_CLIENT_REQUEST_COUNT_METRIC,
    RESPONSES_API_ENGINE_IAPI_TTFT_DURATION_METRIC,
    RESPONSES_API_ENGINE_SERVICE_TBT_DURATION_METRIC,
    RESPONSES_API_ENGINE_SERVICE_TTFT_DURATION_METRIC,
    TOOL_CALL_COUNT_METRIC,
    TOOL_CALL_DURATION_METRIC,
    TURN_COST_MICROUSD_METRIC,
    TURN_TOKEN_USAGE_METRIC,
]

public enum MetricsExporter: Equatable, Sendable {
    case otlp(OtelExporter)
    case inMemory
}

public struct MetricsConfig: Sendable {
    public var environment: String
    public var serviceName: String
    public var serviceVersion: String
    public var exporter: MetricsExporter
    public var exportInterval: Duration?
    public var runtimeReader: Bool
    var statsigDisabledMetrics: [String]
    public var defaultTags: [String: String]

    public init(
        environment: String,
        serviceName: String,
        serviceVersion: String,
        exporter: MetricsExporter,
        exportInterval: Duration? = nil,
        runtimeReader: Bool = false,
        defaultTags: [String: String] = [:]
    ) {
        self.environment = environment
        self.serviceName = serviceName
        self.serviceVersion = serviceVersion
        self.exporter = exporter
        self.exportInterval = exportInterval
        self.runtimeReader = runtimeReader
        if case .otlp(.statsig) = exporter {
            self.statsigDisabledMetrics = CodexOtel.statsigDisabledMetrics
        } else {
            self.statsigDisabledMetrics = []
        }
        self.defaultTags = defaultTags
    }

    public static func otlp(
        environment: String,
        serviceName: String,
        serviceVersion: String,
        exporter: OtelExporter
    ) -> MetricsConfig {
        MetricsConfig(
            environment: environment,
            serviceName: serviceName,
            serviceVersion: serviceVersion,
            exporter: .otlp(exporter)
        )
    }

    public static func inMemory(
        environment: String,
        serviceName: String,
        serviceVersion: String
    ) -> MetricsConfig {
        MetricsConfig(
            environment: environment,
            serviceName: serviceName,
            serviceVersion: serviceVersion,
            exporter: .inMemory
        )
    }

    public func withExportInterval(_ interval: Duration) -> MetricsConfig {
        var copy = self
        copy.exportInterval = interval
        return copy
    }

    public func withRuntimeReader() -> MetricsConfig {
        var copy = self
        copy.runtimeReader = true
        return copy
    }

    public func withTag(key: String, value: String) throws -> MetricsConfig {
        try validateTagKey(key)
        try validateTagValue(value)
        var copy = self
        copy.defaultTags[key] = value
        return copy
    }
}
