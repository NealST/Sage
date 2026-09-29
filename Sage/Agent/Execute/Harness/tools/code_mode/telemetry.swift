//
//  telemetry.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/code_mode/telemetry.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Analytics / tracing emit wait on Session services.
//

import CodexProtocol
import Foundation

enum CodeModeToolCallStatus: String, Equatable, Sendable {
    case started
    case succeeded
    case failed
}

struct CodeModeToolCallGuard {
    var threadId: String
    var turnId: String
    var callId: String
    var cellId: String?
    var toolName: String
    var startedAt: Date
    var status: CodeModeToolCallStatus

    init(
        threadId: String,
        turnId: String,
        callId: String,
        toolName: String,
        cellId: String? = nil
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.callId = callId
        self.cellId = cellId
        self.toolName = toolName
        self.startedAt = Date()
        self.status = .started
    }

    mutating func markSucceeded() { status = .succeeded }
    mutating func markFailed() { status = .failed }
}
