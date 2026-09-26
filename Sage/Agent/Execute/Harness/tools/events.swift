//
//  events.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/events.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Session event emission waits for Phase 5. Types and begin/end helpers
//  are kept so handlers can record structured tool-call facts.
//

import CodexProtocol
import Foundation

struct ToolCallEvent: Equatable, Sendable {
    var callId: String
    var toolName: ToolName
    var startedAt: Date
    var finishedAt: Date?
    var success: Bool?
}

final class ToolCallEventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ToolCallEvent] = []

    func begin(_ invocation: ToolInvocation) {
        lock.lock()
        events.append(
            ToolCallEvent(
                callId: invocation.callId,
                toolName: invocation.toolName,
                startedAt: invocation.clock()
            )
        )
        lock.unlock()
    }

    func finish(callId: String, success: Bool) {
        lock.lock()
        if let index = events.lastIndex(where: { $0.callId == callId && $0.finishedAt == nil }) {
            events[index].finishedAt = Date()
            events[index].success = success
        }
        lock.unlock()
    }

    func recorded() -> [ToolCallEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
