//
//  mcp_approval_meta.swift
//  CodexProtocol
//
//  Port of codex-rs/protocol/src/mcp_approval_meta.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Privileged approval metadata keys shared with the MCP elicitation router.
//  Constant names keep upstream's SCREAMING_SNAKE_CASE so cross-references
//  stay greppable (plan §5.3).
//

import Foundation

/// Identifies privileged Codex approvals. Changing this key or adding another
/// privileged discriminator requires updating the MCP elicitation router's
/// form-forwarding safeguards.
public let APPROVAL_KIND_KEY = "codex_approval_kind"
public let APPROVAL_KIND_MCP_TOOL_CALL = "mcp_tool_call"
public let APPROVAL_KIND_BROWSER_AUTH = "browser_auth"
public let APPROVAL_KIND_TOOL_SUGGESTION = "tool_suggestion"
/// Marks requests that need user input even when their form schema is empty.
public let REQUIRES_USER_INPUT_KEY = "codex_requires_user_input"
public let REQUEST_TYPE_KEY = "codex_request_type"
public let REQUEST_TYPE_APPROVAL_REQUEST = "approval_request"
public let STRICT_AUTO_REVIEW_KEY = "codex_strict_auto_review"
/// Marks a sensitive action requiring synchronous review when routed to
/// automatic review. Absent or false preserves the existing approval path.
public let SENSITIVE_ACTION_KEY = "codex_sensitive_action"
public let APPROVALS_REVIEWER_KEY = "approvals_reviewer"
public let PERSIST_KEY = "persist"
public let PERSIST_SESSION = "session"
public let PERSIST_ALWAYS = "always"
public let SOURCE_KEY = "source"
public let SOURCE_CONNECTOR = "connector"
public let CONNECTOR_ID_KEY = "connector_id"
public let CONNECTOR_NAME_KEY = "connector_name"
public let CONNECTOR_DESCRIPTION_KEY = "connector_description"
public let TOOL_NAME_KEY = "tool_name"
public let TOOL_TITLE_KEY = "tool_title"
public let TOOL_DESCRIPTION_KEY = "tool_description"
public let TOOL_PARAMS_KEY = "tool_params"
public let TOOL_PARAMS_DISPLAY_KEY = "tool_params_display"
