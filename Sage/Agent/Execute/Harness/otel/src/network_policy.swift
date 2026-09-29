//
//  network_policy.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/network_policy.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  OTLP SDK PolicyExporter / RuntimeHttpClient are no-ops. Sage does not
//  ship the OpenTelemetry SDK (plan §Phase 10).
//

import Foundation

/// Placeholder for the upstream `PolicyExporter<E>` wrapper. Export stays local.
public struct PolicyExporter: Sendable {
    public var denied: Bool

    public init(denied: Bool = false) {
        self.denied = denied
    }

    public func acquire() throws {
        if denied {
            throw MetricsError.invalidConfig(message: "telemetry export denied by network policy")
        }
    }
}
