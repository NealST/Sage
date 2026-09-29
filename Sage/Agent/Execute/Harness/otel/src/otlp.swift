//
//  otlp.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/otlp.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Header map helper is faithful. TLS / reqwest client builders are
//  omitted because OTLP export is not installed.
//

import Foundation

func buildHeaderMap(_ headers: [String: String]) -> [String: String] {
    var map: [String: String] = [:]
    for (key, value) in headers {
        if !key.isEmpty, !value.contains(where: { $0.isNewline }) {
            map[key] = value
        }
    }
    return map
}

func otlpConfigError(_ message: String) -> MetricsError {
    .invalidConfig(message: message)
}
