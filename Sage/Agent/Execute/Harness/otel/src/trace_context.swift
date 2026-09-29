//
//  trace_context.swift
//  CodexOtel
//
//  Port of codex-rs/otel/src/trace_context.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  W3C header parse / tracestate validation is faithful. Span-backed
//  current_span_* helpers return nil (no OpenTelemetry SDK).
//

import CodexProtocol
import CodexUtils
import Foundation
import os

private let traceparentEnvVar = "TRACEPARENT"
private let tracestateEnvVar = "TRACESTATE"
private let tracestateEntries = OSAllocatedUnfairLock(initialState: [String: [String: String]]())
private let traceparentContext = OSAllocatedUnfairLock<W3cTraceContext?>(
    initialState: loadTraceparentContext()
)

public func currentSpanW3cTraceContext() -> W3cTraceContext? {
    nil
}

public func currentSpanTraceId() -> String? {
    nil
}

public func spanW3cTraceContext() -> W3cTraceContext? {
    nil
}

public func injectSpanW3cTraceHeaders(_ headers: inout [String: String]) -> Bool {
    guard let trace = currentSpanW3cTraceContext() else { return false }
    headers["traceparent"] = trace.traceparent
    if let tracestate = trace.tracestate {
        headers["tracestate"] = tracestate
    } else {
        headers.removeValue(forKey: "tracestate")
    }
    return true
}

public func contextFromW3cTraceContext(_ trace: W3cTraceContext) -> W3cTraceContext? {
    contextFromTraceHeaders(traceparent: trace.traceparent, tracestate: trace.tracestate)
}

public func setParentFromW3cTraceContext(_ trace: W3cTraceContext) -> Bool {
    contextFromW3cTraceContext(trace) != nil
}

public func setParentFromContext(_: W3cTraceContext) {}

public func traceparentContextFromEnv() -> W3cTraceContext? {
    traceparentContext.withLock { $0 }
}

public func contextFromTraceHeaders(traceparent: String?, tracestate: String?) -> W3cTraceContext? {
    guard let traceparent, isValidTraceparent(traceparent) else { return nil }
    return W3cTraceContext(traceparent: traceparent, tracestate: tracestate)
}

func setTracestateEntries(_ entries: [String: [String: String]]) throws {
    try validateTracestateEntries(entries)
    tracestateEntries.withLock { $0 = entries }
}

/// Validates configured tracestate members before they are propagated.
public func validateTracestateEntries(_ entries: [String: [String: String]]) throws {
    for (key, fields) in entries {
        try validateTracestateMember(key, fields: fields)
    }
}

/// Validates one configured tracestate member and its encoded field value.
public func validateTracestateMember(_ memberKey: String, fields: [String: String]) throws {
    guard isConfiguredTracestateFieldKey(memberKey) else {
        throw IOError.invalidInput("invalid configured tracestate member key \(memberKey)")
    }
    _ = try encodeTracestateMemberFields(memberKey, fields: fields)
}

func encodeTracestateMemberFields(
    _ memberKey: String,
    fields: [String: String]
) throws -> (String, String) {
    var encoded: [String] = []
    for (fieldKey, value) in fields.sorted(by: { $0.key < $1.key }) {
        guard isConfiguredTracestateFieldKey(fieldKey) else {
            throw IOError.invalidInput(
                "invalid configured tracestate field key \(memberKey).\(fieldKey)"
            )
        }
        guard isConfiguredTracestateFieldValue(value) else {
            throw IOError.invalidInput(
                "invalid configured tracestate value for \(memberKey).\(fieldKey)"
            )
        }
        encoded.append("\(fieldKey):\(value)")
    }
    let value = encoded.joined(separator: ";")
    guard isHeaderSafeTracestateMemberValue(value) else {
        throw IOError.invalidInput("invalid configured tracestate value for \(memberKey)")
    }
    return (memberKey, value)
}

func mergeTracestateEntries(
    _ tracestate: String?,
    configured: [String: [String: String]]
) -> String? {
    var members: [(String, String)] = []
    if let tracestate {
        for member in tracestate.split(separator: ",") {
            let trimmed = member.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            members.append((key, value))
        }
    }
    for (key, fields) in configured.sorted(by: { $0.key < $1.key }).reversed() {
        let existing = members.first(where: { $0.0 == key })?.1
        let merged = mergeTracestateMemberFields(existing, configured: fields)
        members.removeAll { $0.0 == key }
        members.insert((key, merged), at: 0)
    }
    let header = members
        .map { "\($0.0)=\($0.1)" }
        .joined(separator: ",")
    return header.isEmpty ? nil : header
}

private func mergeTracestateMemberFields(
    _ existing: String?,
    configured: [String: String]
) -> String {
    var fields: [String] = []
    var seen = Set<String>()
    if let existing {
        for field in existing.split(separator: ";") where !field.isEmpty {
            let raw = String(field)
            if let colon = raw.firstIndex(of: ":") {
                let fieldKey = String(raw[..<colon])
                if let value = configured[fieldKey] {
                    if seen.insert(fieldKey).inserted {
                        fields.append("\(fieldKey):\(value)")
                    }
                    continue
                }
                seen.insert(fieldKey)
            }
            fields.append(raw)
        }
    }
    for (fieldKey, value) in configured.sorted(by: { $0.key < $1.key })
    where !seen.contains(fieldKey) {
        fields.append("\(fieldKey):\(value)")
    }
    return fields.joined(separator: ";")
}

private func isConfiguredTracestateFieldKey(_ fieldKey: String) -> Bool {
    !fieldKey.isEmpty
        && fieldKey.utf8.allSatisfy { byte in
            byte >= 0x21 && byte <= 0x7E && byte != UInt8(ascii: ":")
                && byte != UInt8(ascii: ";") && byte != UInt8(ascii: ",")
                && byte != UInt8(ascii: "=")
        }
}

private func isConfiguredTracestateFieldValue(_ value: String) -> Bool {
    value.utf8.allSatisfy { isTracestateMemberValueByte($0) && $0 != UInt8(ascii: ";") }
}

private func isHeaderSafeTracestateMemberValue(_ value: String) -> Bool {
    value.isEmpty
        || (value.utf8.allSatisfy(isTracestateMemberValueByte)
            && value.utf8.last != UInt8(ascii: " "))
}

private func isTracestateMemberValueByte(_ byte: UInt8) -> Bool {
    byte >= 0x20 && byte <= 0x7E && byte != UInt8(ascii: ",") && byte != UInt8(ascii: "=")
}

private func isValidTraceparent(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 4, parts[0] == "00" else { return false }
    let traceId = parts[1]
    let spanId = parts[2]
    let flags = parts[3]
    return traceId.count == 32 && spanId.count == 16 && flags.count == 2
        && traceId.allSatisfy(\.isHexDigit)
        && spanId.allSatisfy(\.isHexDigit)
        && flags.allSatisfy(\.isHexDigit)
        && traceId != String(repeating: "0", count: 32)
        && spanId != String(repeating: "0", count: 16)
}

private func loadTraceparentContext() -> W3cTraceContext? {
    guard let traceparent = ProcessInfo.processInfo.environment[traceparentEnvVar] else {
        return nil
    }
    let tracestate = ProcessInfo.processInfo.environment[tracestateEnvVar]
    if let context = contextFromTraceHeaders(traceparent: traceparent, tracestate: tracestate) {
        return context
    }
    Logger(subsystem: "codex.otel", category: "trace")
        .warning("TRACEPARENT is set but invalid; ignoring trace context")
    return nil
}
