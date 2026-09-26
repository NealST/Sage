//
//  lib.swift
//  CodexHooks
//
//  Port of codex-rs/hooks/src/lib.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Event request/outcome types stay unstarted with the rest of the hooks
//  crate. This file ports the event-name tables and persisted hook-state
//  keys. Protocol `HookEventName` is still a smaller subset, so key labels
//  take the upstream PascalCase names as strings.
//

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
public func hookEventKeyLabel(_ eventName: String) -> String {
    switch eventName {
    case "PreToolUse": return "pre_tool_use"
    case "PermissionRequest": return "permission_request"
    case "PostToolUse": return "post_tool_use"
    case "PreCompact": return "pre_compact"
    case "PostCompact": return "post_compact"
    case "SessionStart": return "session_start"
    case "SessionEnd": return "session_end"
    case "UserPromptSubmit": return "user_prompt_submit"
    case "SubagentStart": return "subagent_start"
    case "SubagentStop": return "subagent_stop"
    case "Stop": return "stop"
    case "Interrupt": return "interrupt"
    default: return eventName
    }
}

/// Builds the persisted config-state key for one discovered hook handler.
public func hookKey(
    keySource: String,
    eventName: String,
    groupIndex: Int,
    handlerIndex: Int
) -> String {
    "\(keySource):\(hookEventKeyLabel(eventName)):\(groupIndex):\(handlerIndex)"
}
