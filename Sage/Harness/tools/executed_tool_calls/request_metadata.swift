//
//  request_metadata.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/executed_tool_calls/request_metadata.rs
//  (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  History / rollout persistence waits for Phase 7. This keeps the
//  per-call metadata budget helpers.
//

import Foundation

let MAX_EXECUTED_TOOL_CALL_ARGUMENT_BYTES = 8 * 1024
let MAX_EXECUTED_TOOL_CALL_FULL_ARGUMENT_BYTES_PER_OUTPUT = 32 * 1024

func truncatedToolArgument(_ arguments: String, byteBudget: Int = MAX_EXECUTED_TOOL_CALL_ARGUMENT_BYTES) -> String {
    guard arguments.utf8.count > byteBudget else { return arguments }
    var end = arguments.startIndex
    var used = 0
    for (index, character) in arguments.enumerated() {
        let next = used + String(character).utf8.count
        if next > byteBudget { break }
        used = next
        end = arguments.index(arguments.startIndex, offsetBy: index + 1)
    }
    return String(arguments[..<end])
}

struct ExecutedToolRequestMetadata: Equatable, Sendable {
    var callId: String
    var toolName: String
    var arguments: String
    var truncated: Bool
}
