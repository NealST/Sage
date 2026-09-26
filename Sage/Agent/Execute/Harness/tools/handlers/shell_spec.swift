//
//  shell_spec.swift
//  Sage
//
//  Port of codex-rs/core/src/tools/handlers/shell_spec.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Windows shell guidance is kept but not selected on macOS.
//

import CodexProtocol

func createExecCommandTool(
    options: CommandToolOptions,
    includeEnvironmentId: Bool = false,
    includeShellParameter: Bool = true,
    includeWindowsShellGuidance: Bool = false
) -> ToolSpec {
    let yieldTimeMsDescription = includeWindowsShellGuidance
        ? "Maximum time to wait before returning a session ID for a still-running command. Commands that finish sooner return immediately. For ordinary commands, omit this parameter to use the 10000 ms default. Effective range on Windows is 10000-30000 ms."
        : "Wait before yielding output. Defaults to 10000 ms; effective range is 250-30000 ms."
    var properties: [String: JsonSchema] = [
        "cmd": .string("Shell command to execute."),
        "workdir": .string("Working directory for the command. Defaults to the turn cwd."),
        "tty": .boolean("True allocates a PTY for the command; false or omitted uses plain pipes."),
        "yield_time_ms": .number(yieldTimeMsDescription),
        "max_output_tokens": .number(
            "Output token budget. Defaults to 10000 tokens; larger requests may be capped by policy."
        ),
    ]
    if includeShellParameter {
        properties["shell"] = .string("Shell binary to launch. Defaults to the user's default shell.")
    }
    if options.allowLoginShell {
        properties["login"] = .boolean(
            "True runs the shell with -l/-i semantics; false disables them. Defaults to true."
        )
    }
    if includeEnvironmentId {
        properties["environment_id"] = .string(
            "Environment id from <environment_context>. Omit to use the primary environment."
        )
    }
    for (key, value) in createApprovalParameters(options.execPermissionApprovalsEnabled) {
        properties[key] = value
    }
    let description = includeWindowsShellGuidance
        ? "Runs a command in a PTY, returning output or a session ID for ongoing interaction.\n\n\(windowsShellGuidance())"
        : "Runs a command in a PTY, returning output or a session ID for ongoing interaction."
    return .function(
        ResponsesApiTool(
            name: "exec_command",
            description: description,
            strict: false,
            parameters: .object(properties, required: ["cmd"], additionalProperties: false),
            outputSchema: unifiedExecOutputSchema()
        )
    )
}

func createWriteStdinTool() -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: "write_stdin",
            description: "Writes characters to an existing unified exec session and returns recent output.",
            strict: false,
            parameters: .object(
                [
                    "session_id": .number("Identifier of the running unified exec session."),
                    "chars": .string(
                        "Bytes to write to stdin. Defaults to empty, which polls without writing."
                    ),
                    "yield_time_ms": .number(
                        "Wait before yielding output. Non-empty writes default to 250 ms and cap at 30000 ms; empty polls wait 5000-300000 ms by default."
                    ),
                    "max_output_tokens": .number(
                        "Output token budget. Defaults to 10000 tokens; larger requests may be capped by policy."
                    ),
                ],
                required: ["session_id"],
                additionalProperties: false
            ),
            outputSchema: unifiedExecOutputSchema()
        )
    )
}

func createRequestPermissionsTool(_ description: String) -> ToolSpec {
    .function(
        ResponsesApiTool(
            name: "request_permissions",
            description: description,
            strict: false,
            parameters: .object(
                [
                    "reason": .string(
                        "Optional short explanation for why additional permissions are needed."
                    ),
                    "environment_id": .string(
                        "Environment id from <environment_context>. Omit to use the primary environment."
                    ),
                    "permissions": permissionProfileSchema(),
                ],
                required: ["permissions"],
                additionalProperties: false
            )
        )
    )
}

func requestPermissionsToolDescription() -> String {
    "Request additional filesystem or network permissions from the user and wait for the client to grant a subset of the requested permission profile. Use environment_id to target a specific attached environment; omit it to use the primary environment. Relative filesystem paths resolve against the selected environment cwd. Granted permissions apply automatically to later shell-like commands in the current turn, or for the rest of the session if the client approves them at session scope."
}

struct CommandToolOptions: Equatable, Sendable {
    var allowLoginShell: Bool
    var execPermissionApprovalsEnabled: Bool
}

func unifiedExecOutputSchema() -> HarnessJSON {
    .object([
        "type": .string("object"),
        "properties": .object([
            "chunk_id": .object([
                "type": .string("string"),
                "description": .string("Chunk identifier included when the response reports one."),
            ]),
            "wall_time_seconds": .object([
                "type": .string("number"),
                "description": .string("Elapsed wall time spent waiting for output in seconds."),
            ]),
            "exit_code": .object([
                "type": .string("number"),
                "description": .string("Process exit code when the command finished during this call."),
            ]),
            "session_id": .object([
                "type": .string("number"),
                "description": .string(
                    "Session identifier to pass to write_stdin when the process is still running."
                ),
            ]),
            "original_token_count": .object([
                "type": .string("number"),
                "description": .string("Approximate token count before output truncation."),
            ]),
            "output": .object([
                "type": .string("string"),
                "description": .string("Command output text, possibly truncated."),
            ]),
        ]),
        "required": .array([.string("wall_time_seconds"), .string("output")]),
        "additionalProperties": .bool(false),
    ])
}

func createApprovalParameters(_ execPermissionApprovalsEnabled: Bool) -> [String: JsonSchema] {
    var values = ["use_default"]
    if execPermissionApprovalsEnabled {
        values.append("with_additional_permissions")
    }
    values.append("require_escalated")
    let sandboxDescription = execPermissionApprovalsEnabled
        ? "Per-command sandbox override. Defaults to `use_default`; use `with_additional_permissions` with `additional_permissions`, or `require_escalated` for unsandboxed execution."
        : "Per-command sandbox override. Defaults to `use_default`; use `require_escalated` for unsandboxed execution."
    var properties: [String: JsonSchema] = [
        "sandbox_permissions": .stringEnum(values, description: sandboxDescription),
        "justification": .string("User-facing approval question for `require_escalated`; omit otherwise."),
        "prefix_rule": .array(
            .string(),
            description: #"Reusable approval prefix for `cmd`, only with `sandbox_permissions: "require_escalated"`; for example ["git", "pull"]."#
        ),
    ]
    if execPermissionApprovalsEnabled {
        var extra = permissionProfileSchema()
        extra.description =
            "Sandboxed filesystem or network access for this command; only with `sandbox_permissions: \"with_additional_permissions\"`."
        properties["additional_permissions"] = extra
    }
    return properties
}

func permissionProfileSchema() -> JsonSchema {
    var schema = JsonSchema.object(
        [
            "network": networkPermissionsSchema(),
            "file_system": fileSystemPermissionsSchema(),
        ],
        additionalProperties: false
    )
    schema.description = "Filesystem or network access request."
    return schema
}

func networkPermissionsSchema() -> JsonSchema {
    var schema = JsonSchema.object(
        [
            "enabled": .boolean("True requests network access; false or omitted requests none.")
        ],
        additionalProperties: false
    )
    schema.description = "Network access request."
    return schema
}

func fileSystemPermissionsSchema() -> JsonSchema {
    var schema = JsonSchema.object(
        [
            "read": .array(
                .string(),
                description: "Absolute paths to grant read access; omit when none are needed."
            ),
            "write": .array(
                .string(),
                description: "Absolute paths to grant write access; omit when none are needed."
            ),
        ],
        additionalProperties: false
    )
    schema.description = "Filesystem access request."
    return schema
}

func windowsShellGuidance() -> String {
    """
    Windows safety rules:
    - Do not compose destructive filesystem commands across shells. Do not enumerate paths in PowerShell and then pass them to `cmd /c`, batch builtins, or another shell for deletion or moving. Use one shell end-to-end, prefer native PowerShell cmdlets such as `Remove-Item` / `Move-Item` with `-LiteralPath`, and avoid string-built shell commands for file operations.
    - Before any recursive delete or move on Windows, verify the resolved absolute target paths stay within the intended workspace or explicitly named target directory. Never issue a recursive delete or move against a computed path if the final target has not been checked.
    - When using `Start-Process` to launch a background helper or service, pass `-WindowStyle Hidden` unless the user explicitly asked for a visible interactive window. Use visible windows only for interactive tools the user needs to see or control.
    """
}
