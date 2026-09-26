//
//  responses_headers.swift
//  CodexCore
//
//  Port of codex-rs/core/src/responses_headers.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  http::HeaderMap is [String: String]. Header names are recorded for Debug.
//

public struct CodexResponsesHeaders: Sendable {
    public var model: String
    public var headers: [String: String]

    public init(model: String, headers: [String: String] = [:]) {
        self.model = model
        self.headers = headers
    }
}

extension CodexResponsesHeaders: CustomDebugStringConvertible {
    public var debugDescription: String {
        "CodexResponsesHeaders(model: \(model), header_names: \(headers.keys.sorted()))"
    }
}
