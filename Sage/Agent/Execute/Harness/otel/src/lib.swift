//
//  lib.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Public types and install helpers. TelemetryAuthMode / ToolDecisionSource
//  match upstream. OTLP / Statsig export is in-memory only.
//

import CodexProtocol
import CodexUtils

public enum ToolDecisionSource: String, Codable, Equatable, Sendable {
    case automatedReviewer = "automated_reviewer"
    case config
    case user
}

/// Coarsens the authentication domain into the dimensions used by telemetry.
public enum TelemetryAuthMode: String, Equatable, Sendable {
    case apiKey = "api_key"
    case chatgpt
}

extension TelemetryAuthMode {
    public init(_ mode: AuthMode) {
        switch mode {
        case .apiKey, .bedrockApiKey, .bedrockAccessKeys:
            self = .apiKey
        case .chatgpt, .chatgptAuthTokens, .headers, .agentIdentity, .personalAccessToken:
            self = .chatgpt
        }
    }
}

/// Install externally managed, non-Statsig process-global metrics.
public func installGlobalMetrics(_ metrics: MetricsClient) -> MetricsClient {
    installGlobal(metrics)
}

/// Start a metrics timer using the globally installed metrics client.
public func startGlobalTimer(_ name: String, tags: [(String, String)] = []) throws -> Timer {
    guard let metrics = globalMetricsClient() else {
        throw MetricsError.exporterDisabled
    }
    return metrics.startTimer(name, tags: tags)
}

/// Returns the resolved Statsig metrics settings for the globally installed
/// OTEL metrics client, if the active metrics exporter is Statsig.
public func globalStatsigMetricsSettings() -> StatsigMetricsSettings? {
    globalStatsigSettings()
}
