//
//  mod.swift
//  CodexState
//
//  Port of codex-rs/state/src/model/mod.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Swift has no crate-level `pub use`; the types listed below are public
//  in the CodexState module via their defining files.
//

import Foundation

public struct StateModelError: Error, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

func stateEncodeRFC3339(_ date: Date) -> String {
    ISO8601DateFormatter.withFractionalSeconds.string(from: date)
}

func stateDecodeRFC3339(_ string: String) throws -> Date {
    if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string)
        ?? ISO8601DateFormatter.internetDateTime.date(from: string)
    {
        return date
    }
    throw StateModelError("invalid RFC3339 timestamp: \(string)")
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
