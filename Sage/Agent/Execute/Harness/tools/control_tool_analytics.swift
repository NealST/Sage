//
//  control_tool_analytics.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/control_tool_analytics.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Analytics client waits for Phase 5 session services. The guard still
//  records start/finish timestamps for local tests.
//

import Foundation

enum ControlToolCallStatus: Equatable, Sendable {
    case completed
    case failed
    case interrupted
}

final class ControlToolCallGuard: @unchecked Sendable {
    let invocation: ToolInvocation
    let startedAt: Date
    private(set) var completedAt: Date?
    private(set) var status: ControlToolCallStatus = .interrupted

    init(_ invocation: ToolInvocation) {
        self.invocation = invocation
        startedAt = invocation.clock()
    }

    func finish(_ status: ControlToolCallStatus) {
        completedAt = invocation.clock()
        self.status = status
    }
}
