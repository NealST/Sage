//
//  lib.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Event-name tables and persisted hook-state keys use protocol
//  `HookEventName`. Event run paths go through ClaudeHooksEngine.
//

import CodexProtocol
import Foundation

/// Hook event names as they appear in hooks JSON and config files.
public let HOOK_EVENT_NAMES: [String] = [
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "SessionStart",
    "SessionEnd",
    "UserPromptSubmit",
    "SubagentStart",
    "SubagentStop",
    "Stop",
    "Interrupt",
]

/// Hook event names whose matcher fields are meaningful during dispatch.
public let HOOK_EVENT_NAMES_WITH_MATCHERS: [String] = [
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "SessionStart",
    "SessionEnd",
    "SubagentStart",
    "SubagentStop",
]

/// Returns the hook event label used in persisted hook-state keys.
public func hookEventKeyLabel(_ eventName: HookEventName) -> String {
    switch eventName {
    case .preToolUse: return "pre_tool_use"
    case .permissionRequest: return "permission_request"
    case .postToolUse: return "post_tool_use"
    case .preCompact: return "pre_compact"
    case .postCompact: return "post_compact"
    case .sessionStart: return "session_start"
    case .sessionEnd: return "session_end"
    case .userPromptSubmit: return "user_prompt_submit"
    case .subagentStart: return "subagent_start"
    case .subagentStop: return "subagent_stop"
    case .stop: return "stop"
    case .interrupt: return "interrupt"
    }
}

/// Builds the persisted config-state key for one discovered hook handler.
public func hookKey(
    keySource: String,
    eventName: HookEventName,
    groupIndex: Int,
    handlerIndex: Int
) -> String {
    "\(keySource):\(hookEventKeyLabel(eventName)):\(groupIndex):\(handlerIndex)"
}

/// PascalCase JSON event name used on hook stdin.
public func hookEventWireName(_ eventName: HookEventName) -> String {
    switch eventName {
    case .preToolUse: return "PreToolUse"
    case .permissionRequest: return "PermissionRequest"
    case .postToolUse: return "PostToolUse"
    case .preCompact: return "PreCompact"
    case .postCompact: return "PostCompact"
    case .sessionStart: return "SessionStart"
    case .sessionEnd: return "SessionEnd"
    case .userPromptSubmit: return "UserPromptSubmit"
    case .subagentStart: return "SubagentStart"
    case .subagentStop: return "SubagentStop"
    case .stop: return "Stop"
    case .interrupt: return "Interrupt"
    }
}
