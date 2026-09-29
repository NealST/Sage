//
//  config.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Exporter / TLS / Settings types are faithful. `HttpClientFactory` is
//  omitted (no HTTP client crate). Statsig stays off in DEBUG builds.
//  OTLP export is not installed (plan §Phase 10: minimal metrics).
//

import CodexUtils
import Foundation

let statsigOtlpHttpEndpoint = "https://ab.chatgpt.com/otlp/v1/metrics"
let statsigApiKeyHeader = "statsig-api-key"
let statsigApiKey = "client-MkRuleRQBd6qakfnDYqJVR9JuXcY57Ljly3vi5JVUIO"

func resolveExporter(_ exporter: OtelExporter) -> OtelExporter {
    switch exporter {
    case .statsig:
        #if DEBUG
        return .none
        #else
        return .otlpHttp(
            endpoint: statsigOtlpHttpEndpoint,
            headers: [statsigApiKeyHeader: statsigApiKey],
            protocol: .json,
            tls: nil
        )
        #endif
    default:
        return exporter
    }
}

/// Validates configured span attributes before they are attached to exported spans.
public func validateSpanAttributes(_ attributes: [String: String]) throws {
    if attributes.keys.contains(where: { $0.isEmpty }) {
        throw IOError.invalidInput("configured span attribute key must not be empty")
    }
}

public struct OtelSettings: Sendable {
    public var environment: String
    public var serviceName: String
    public var serviceVersion: String
    public var codexHome: String
    public var exporter: OtelExporter
    public var traceExporter: OtelExporter
    public var metricsExporter: OtelExporter
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
        self.runtimeMetrics = runtimeMetrics
        self.spanAttributes = spanAttributes
        self.tracestate = tracestate
    }
}

/// Resolved Statsig metrics settings that another process can use to recreate
/// the built-in metrics exporter configuration without receiving generic
/// exporter credentials in-process.
public struct StatsigMetricsSettings: Codable, Equatable, Sendable {
    public var environment: String

    public init(environment: String) {
        self.environment = environment
    }
}

public enum OtelHttpProtocol: Equatable, Sendable {
    case binary
    case json
}

public struct OtelTlsConfig: Equatable, Sendable {
    public var caCertificate: AbsolutePathBuf?
    public var clientCertificate: AbsolutePathBuf?
    public var clientPrivateKey: AbsolutePathBuf?

    public init(
        caCertificate: AbsolutePathBuf? = nil,
        clientCertificate: AbsolutePathBuf? = nil,
        clientPrivateKey: AbsolutePathBuf? = nil
    ) {
        self.caCertificate = caCertificate
        self.clientCertificate = clientCertificate
        self.clientPrivateKey = clientPrivateKey
    }
}

public enum OtelExporter: Equatable, Sendable {
    case none
    /// Statsig metrics ingestion exporter using Codex-internal defaults.
    case statsig
    case otlpGrpc(endpoint: String, headers: [String: String], tls: OtelTlsConfig?)
    case otlpHttp(
        endpoint: String,
        headers: [String: String],
        protocol: OtelHttpProtocol,
        tls: OtelTlsConfig?
    )
}
