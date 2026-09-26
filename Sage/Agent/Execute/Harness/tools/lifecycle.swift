//
//  lifecycle.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/lifecycle.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Extension contributors and Session stores wait for Phase 5 / Phase 9.
//  The notify functions keep the call shape so later wiring can subscribe.
//

import CodexProtocol
import CodexUtils

enum ToolCallOutcome: Equatable, Sendable {
    case completed
    case failed
    case aborted
}

func notifyToolStart(_ invocation: ToolInvocation) {}

func notifyCommandStart(
    callId: String,
    command: [String],
    cwd: PathUri
) {}

func notifyToolFinish(_ invocation: ToolInvocation, outcome: ToolCallOutcome) {}

func notifyToolAborted(
    callId: String,
    toolName: ToolName,
    source: ToolCallSource
) {}
