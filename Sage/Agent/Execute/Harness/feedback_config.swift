//
//  feedback_config.swift
//  CodexCore
//
//  Port of codex-rs/core/src/feedback_config.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Searchable usage diagnostics from an explicit scalar-only allowlist.
//  Never include prompts, paths, credentials, provider endpoints, or raw
//  configuration. The Sage `Config` type lives in the app module, so callers
//  pass already-extracted scalars.
//

import CodexProtocol
import Foundation

public func usageTags(_ values: [String: JSONValue], featureFlags: [String: Bool] = [:]) -> [String: String] {
    var tags: [String: String] = [:]
    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
        switch value {
        case .null:
            tags[key] = "unset"
        case .string(let string):
            tags[key] = string
        default:
            tags[key] = value.jsonString()
        }
    }
    for (key, enabled) in featureFlags.sorted(by: { $0.key < $1.key }) {
        if key == "collab" || key == "spawn_csv" { continue }
        tags["feature.\(key)"] = enabled ? "true" : "false"
    }
    return tags
}

private extension JSONValue {
    func jsonString() -> String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .uint(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return value
        case .null: return "null"
        default:
            guard let data = try? JSONEncoder().encode(self),
                  let text = String(data: data, encoding: .utf8)
            else { return "null" }
            return text
        }
    }
}
