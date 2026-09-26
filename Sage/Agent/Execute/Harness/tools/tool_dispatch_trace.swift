//
//  tool_dispatch_trace.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/tool_dispatch_trace.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Rollout-trace writer waits for Phase 7. This adapter records
//  invocation/result facts in memory.
//

import CodexCore
import CodexProtocol

enum ToolDispatchRequester: Equatable, Sendable {
    case model(modelVisibleCallId: String)
    case codeCell(runtimeCellId: String, runtimeToolCallId: String)
}

enum ToolDispatchPayload: Equatable, Sendable {
    case function(arguments: String)
    case toolSearch(arguments: String)
    case custom(input: String)
}

struct ToolDispatchTrace {
    var invocation: ToolInvocation
    var completedSuccess: Bool?

    static func start(_ invocation: ToolInvocation) -> ToolDispatchTrace {
        ToolDispatchTrace(invocation: invocation)
    }

    mutating func recordCompleted(success: Bool) {
        completedSuccess = success
    }

    mutating func recordFailed(_ error: FunctionCallError) {
        completedSuccess = false
        _ = error
    }
}

func toolDispatchPayload(_ payload: ToolPayload) -> ToolDispatchPayload {
    switch payload {
    case .function(let arguments): return .function(arguments: arguments)
    case .toolSearch(let arguments): return .toolSearch(arguments: arguments.query)
    case .custom(let input): return .custom(input: input)
    }
}
