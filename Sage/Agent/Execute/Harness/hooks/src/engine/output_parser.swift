//
//  output_parser.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/engine/output_parser.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  JSON detection and universal hook-output fields are faithful. Full
//  per-event schema structs wait on schema.swift wire types.
//

import Foundation

public struct HookUniversalOutput: Equatable, Sendable {
    public var `continue`: Bool
    public var stopReason: String?
    public var suppressOutput: Bool
    public var systemMessage: String?

    public init(
        `continue`: Bool = true,
        stopReason: String? = nil,
        suppressOutput: Bool = false,
        systemMessage: String? = nil
    ) {
        self.continue = `continue`
        self.stopReason = stopReason
        self.suppressOutput = suppressOutput
        self.systemMessage = systemMessage
    }
}

public func looksLikeJSON(_ stdout: String) -> Bool {
    let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
}

public func parseUniversalHookOutput(_ stdout: String) -> HookUniversalOutput? {
    guard looksLikeJSON(stdout),
          let data = stdout.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }
    return HookUniversalOutput(
        continue: object["continue"] as? Bool ?? true,
        stopReason: object["stopReason"] as? String ?? object["stop_reason"] as? String,
        suppressOutput: object["suppressOutput"] as? Bool
            ?? object["suppress_output"] as? Bool
            ?? false,
        systemMessage: object["systemMessage"] as? String ?? object["system_message"] as? String
    )
}

public func parseInterrupt(_ stdout: String) -> HookUniversalOutput? {
    parseUniversalHookOutput(stdout)
}
