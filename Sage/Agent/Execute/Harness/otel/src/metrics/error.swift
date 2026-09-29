//
//  error.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/metrics/error.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  ExporterBuild / ProviderShutdown drop OpenTelemetry SDK source errors.
//

import Foundation

public enum MetricsError: Error, Equatable, CustomStringConvertible, Sendable {
    case operationMetadataTooLarge
    case emptyMetricName
    case invalidMetricName(name: String)
    case emptyTagComponent(label: String)
    case invalidTagComponent(label: String, value: String)
    case exporterDisabled
    case negativeCounterIncrement(name: String, inc: Int64)
    case exporterBuild(message: String)
    case invalidConfig(message: String)
    case providerShutdown(message: String)
    case runtimeSnapshotUnavailable
    case runtimeSnapshotCollect(message: String)

    public var description: String {
        switch self {
        case .operationMetadataTooLarge:
            return "operation metrics exceed the metadata size or tag count limit"
        case .emptyMetricName:
            return "metric name cannot be empty"
        case .invalidMetricName(let name):
            return "metric name contains invalid characters: \(name)"
        case .emptyTagComponent(let label):
            return "\(label) cannot be empty"
        case .invalidTagComponent(let label, let value):
            return "\(label) contains invalid characters: \(value)"
        case .exporterDisabled:
            return "metrics exporter is disabled"
        case .negativeCounterIncrement(let name, let inc):
            return "counter increment must be non-negative for \(name): \(inc)"
        case .exporterBuild(let message):
            return "failed to build OTLP metrics exporter: \(message)"
        case .invalidConfig(let message):
            return "invalid OTLP metrics configuration: \(message)"
        case .providerShutdown(let message):
            return "failed to flush or shutdown metrics provider: \(message)"
        case .runtimeSnapshotUnavailable:
            return "runtime metrics snapshot reader is not enabled"
        case .runtimeSnapshotCollect(let message):
            return "failed to collect runtime metrics snapshot from metrics reader: \(message)"
        }
    }
}
