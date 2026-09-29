//
//  targets.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/targets.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//

public let otelTargetPrefix = "codex_otel"
public let otelLogOnlyTarget = "codex_otel.log_only"
public let otelTraceSafeTarget = "codex_otel.trace_safe"

public func isLogExportTarget(_ target: String) -> Bool {
    target.hasPrefix(otelTargetPrefix) && !isTraceSafeTarget(target)
}

public func isTraceSafeTarget(_ target: String) -> Bool {
    target.hasPrefix(otelTraceSafeTarget)
}
