//
//  line_parser.swift
//  CodexThreadStore
//
//  Port of codex-rs/thread-store/src/local/rollout_migration/line_parser.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Compatibility rewrites match the Rust Value transforms. Decode then goes
//  through `decodeRolloutLine`. EventMsg is still a subset, so historical
//  records whose modern type is unported (e.g. `token_count`) fail decode
//  after rewrite and are skipped by the migration reader.
//

import CodexHistory
import CodexProtocol
import CodexRollout
import CodexUtils
import Foundation

public struct LegacyRolloutParseError: Error, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public func parseLegacyRolloutLine(_ bytes: Data) -> Result<RolloutLine?, LegacyRolloutParseError> {
    if bytes.allSatisfy({ $0 == 0x09 || $0 == 0x0A || $0 == 0x0D || $0 == 0x20 }) {
        return .success(nil)
    }
    do {
        let value = try JSONDecoder().decode(JSONValue.self, from: bytes)
        return parseLegacyRolloutValue(value)
    } catch {
        return .failure(LegacyRolloutParseError(String(describing: error)))
    }
}

func parseLegacyRolloutValue(_ value: JSONValue) -> Result<RolloutLine?, LegacyRolloutParseError> {
    if shouldSkipRetiredRecord(value) {
        return .success(nil)
    }
    var value = value
    normalizeLegacyTurnContext(&value)
    normalizeLegacySandboxPolicy(&value)
    normalizeLegacyRateLimitResets(&value)
    normalizeLegacyReviewEntry(&value)
    do {
        try normalizeLegacyCommandCwd(&value)
        return .success(try decodeRolloutLine(value))
    } catch {
        return .failure(LegacyRolloutParseError(String(describing: error)))
    }
}

private func shouldSkipRetiredRecord(_ value: JSONValue) -> Bool {
    if let event = eventType(value),
       event == "guardian_assessment" || event == "thread_name_updated" || event == "undo_completed"
    {
        return true
    }
    if rolloutType(value) == "response_item",
       value.objectValue?["payload"]?.objectValue?["type"]?.stringValue == "ghost_snapshot"
    {
        return true
    }
    return false
}

private func normalizeLegacyTurnContext(_ value: inout JSONValue) {
    guard rolloutType(value) == "turn_context" else { return }
    guard var payload = payloadObject(value) else { return }
    guard case .object(var collaboration) = payload["collaboration_mode"] else { return }
    if collaboration["settings"] != nil { return }
    var settings: [String: JSONValue] = [:]
    for key in ["model", "reasoning_effort", "developer_instructions"] {
        if let existing = collaboration[key] {
            settings[key] = existing
        }
    }
    if !settings.isEmpty {
        collaboration["settings"] = .object(settings)
        payload["collaboration_mode"] = .object(collaboration)
        setPayload(&value, payload)
    }
}

private func normalizeLegacyReviewEntry(_ value: inout JSONValue) {
    guard eventType(value) == "entered_review_mode" else { return }
    guard var payload = payloadObject(value) else { return }
    if payload["target"] != nil { return }
    guard let prompt = payload["prompt"]?.stringValue else { return }
    payload["target"] = .object([
        "type": .string("custom"),
        "instructions": .string(prompt),
    ])
    setPayload(&value, payload)
}

private func normalizeLegacyRateLimitResets(_ value: inout JSONValue) {
    guard eventType(value) == "token_count" else { return }
    guard var payload = payloadObject(value) else { return }
    guard case .object(var rateLimits) = payload["rate_limits"] else { return }
    for windowName in ["primary", "secondary"] {
        guard case .object(var window) = rateLimits[windowName] else { continue }
        guard let resetsAt = window["resets_at"]?.stringValue else { continue }
        guard let date = parseRfc3339Timestamp(resetsAt) else { continue }
        window["resets_at"] = .int(Int64(date.timeIntervalSince1970.rounded(.towardZero)))
        rateLimits[windowName] = .object(window)
    }
    payload["rate_limits"] = .object(rateLimits)
    setPayload(&value, payload)
}

private func normalizeLegacySandboxPolicy(_ value: inout JSONValue) {
    guard rolloutType(value) == "turn_context" else { return }
    guard var payload = payloadObject(value) else { return }
    guard case .object(var sandboxPolicy) = payload["sandbox_policy"] else { return }
    if sandboxPolicy["type"] != nil { return }
    if let mode = sandboxPolicy["mode"] {
        sandboxPolicy["type"] = mode
        payload["sandbox_policy"] = .object(sandboxPolicy)
        setPayload(&value, payload)
    }
}

private func normalizeLegacyCommandCwd(_ value: inout JSONValue) throws {
    guard let event = eventType(value),
          event == "exec_command_begin" || event == "exec_command_end"
    else {
        return
    }
    guard var payload = payloadObject(value) else { return }
    guard let cwd = payload["cwd"]?.stringValue else { return }
    if cwd.hasPrefix("file:") { return }
    do {
        let uri = try PathUri(fromLegacy: LegacyAppPathString.fromString(cwd))
        let encoded = try JSONEncoder().encode(uri)
        payload["cwd"] = try JSONDecoder().decode(JSONValue.self, from: encoded)
        setPayload(&value, payload)
    } catch {
        throw ThreadStoreError.internal("invalid legacy command cwd: \(error)")
    }
}

private func rolloutType(_ value: JSONValue) -> String? {
    value.objectValue?["type"]?.stringValue
}

private func eventType(_ value: JSONValue) -> String? {
    guard rolloutType(value) == "event_msg" else { return nil }
    return value.objectValue?["payload"]?.objectValue?["type"]?.stringValue
}

private func payloadObject(_ value: JSONValue) -> [String: JSONValue]? {
    value.objectValue?["payload"]?.objectValue
}

private func setPayload(_ value: inout JSONValue, _ payload: [String: JSONValue]) {
    guard case .object(var root) = value else { return }
    root["payload"] = .object(payload)
    value = .object(root)
}

func parseRfc3339Timestamp(_ timestamp: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: timestamp) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: timestamp)
}
