//
//  headers.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/requests/headers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `http::HeaderMap` maps to `[String: String]` (lowercase names).
//

import CodexProtocol
import Foundation

public func buildSessionHeaders(sessionId: String?, threadId: String?) -> [String: String] {
    var headers: [String: String] = [:]
    if let sessionId {
        insertHeader(&headers, "session-id", sessionId)
    }
    if let threadId {
        insertHeader(&headers, "thread-id", threadId)
    }
    return headers
}

func subagentHeader(_ source: SessionSource?) -> String? {
    guard case .subAgent(let sub) = source else { return nil }
    switch sub {
    case .review:
        return "review"
    case .compact:
        return "compact"
    case .memoryConsolidation:
        return "memory_consolidation"
    case .threadSpawn:
        return "collab_spawn"
    case .other(let label):
        return label
    }
}

func insertHeader(_ headers: inout [String: String], _ name: String, _ value: String) {
    headers[name.lowercased()] = value
}

func mergeHeaders(_ base: [String: String], _ extra: [String: String]) -> [String: String] {
    var merged = Dictionary(uniqueKeysWithValues: base.map { ($0.key.lowercased(), $0.value) })
    for (name, value) in extra {
        merged[name.lowercased()] = value
    }
    return merged
}

func lowercaseHeaderMap(_ fields: [AnyHashable: Any]) -> [String: String] {
    var headers: [String: String] = [:]
    for (key, value) in fields {
        let name = String(describing: key).lowercased()
        if let string = value as? String {
            headers[name] = string
        } else {
            headers[name] = String(describing: value)
        }
    }
    return headers
}

func applyHeaders(_ request: inout URLRequest, _ headers: [String: String]) {
    for (name, value) in headers {
        request.setValue(value, forHTTPHeaderField: name)
    }
}
