//
//  shared.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/events/shared.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  tracing macros become os.Logger calls on the same target names.
//

import CodexProtocol
import Foundation
import os

private let logOnlyLogger = Logger(subsystem: "codex.otel", category: otelLogOnlyTarget)
private let traceSafeLogger = Logger(subsystem: "codex.otel", category: otelTraceSafeTarget)

func toolNamespace(_ toolName: ToolName) -> String {
    if let namespace = toolName.namespace, !namespace.isEmpty {
        return namespace
    }
    return DEFAULT_FUNCTION_NAMESPACE
}

func otelTimestamp() -> String {
    ISO8601DateFormatter.otelMillis.string(from: Date())
}

func logOtelEvent(_ telemetry: SessionTelemetry, _ fields: [String: String]) {
    var payload = fields
    payload["event.timestamp"] = otelTimestamp()
    payload["conversation.id"] = telemetry.metadata.conversationId.description
    payload["app.version"] = telemetry.metadata.appVersion
    if let authMode = telemetry.metadata.authMode {
        payload["auth_mode"] = authMode
    }
    payload["originator"] = telemetry.metadata.originator
    if let accountId = telemetry.metadata.accountId {
        payload["user.account_id"] = accountId
    }
    if let email = telemetry.metadata.accountEmail {
        payload["user.email"] = email
    }
    payload["terminal.type"] = telemetry.metadata.terminalType
    payload["model"] = telemetry.metadata.model
    payload["slug"] = telemetry.metadata.slug
    logOnlyLogger.info("\(otelFormatFields(payload), privacy: .public)")
}

func traceOtelEvent(_ telemetry: SessionTelemetry, _ fields: [String: String]) {
    var payload = fields
    payload["event.timestamp"] = otelTimestamp()
    payload["conversation.id"] = telemetry.metadata.conversationId.description
    payload["app.version"] = telemetry.metadata.appVersion
    if let authMode = telemetry.metadata.authMode {
        payload["auth_mode"] = authMode
    }
    payload["originator"] = telemetry.metadata.originator
    payload["terminal.type"] = telemetry.metadata.terminalType
    payload["model"] = telemetry.metadata.model
    payload["slug"] = telemetry.metadata.slug
    traceSafeLogger.info("\(otelFormatFields(payload), privacy: .public)")
}

func logAndTraceOtelEvent(
    _ telemetry: SessionTelemetry,
    common: [String: String],
    log: [String: String] = [:],
    trace: [String: String] = [:]
) {
    var logFields = common
    logFields.merge(log) { _, new in new }
    var traceFields = common
    traceFields.merge(trace) { _, new in new }
    logOtelEvent(telemetry, logFields)
    traceOtelEvent(telemetry, traceFields)
}

func otelFormatFields(_ fields: [String: String]) -> String {
    fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: " ")
}

private extension ISO8601DateFormatter {
    static let otelMillis: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
