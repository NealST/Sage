//
//  ShellTool.swift
//  Sage
//

import Foundation

nonisolated struct RunShellCommandTool: AgentTool {
    let definition = ToolDefinition(
        name: "run_shell_command",
        description: """
            Execute a shell command via /bin/zsh -c and return its output (stdout + stderr combined). \
            Working directory must stay inside the active sandbox \
            (home ~/ in General; the project root when a Project is focused). \
            Defaults to the sandbox root. In Project mode, home-directory reads are limited to the \
            project and current model-visible attachments; writes are limited to the project and \
            system temporary directories. Attached paths outside the project remain read-only. \
            Prefer file tools for reads and writes. \
            Default timeout is 30s (max 120s). \
            File writes are denied unless allow_writes is explicitly true; when enabled, writes are \
            limited to the focus root (home or project) and require authorization. \
            `.git` stays read-only unless allow_protected_metadata_writes is true. \
            Network access is denied unless allow_network is explicitly true; requesting it is part of the \
            approval-scoped invocation. \
            Writes to .sage and .agents are denied unless allow_protected_metadata_writes is explicitly true. \
            Output is capped at 50KB. Result format: "[exit N]\\n<output>". \
            Dangerous commands (rm -rf /, sudo, etc.) are blocked. \
            Use for: git, grep, find, python, node, brew, make, and other CLI tools.
            """,
        parameters: .schemaObject(
            properties: [
                "command": .stringProperty("Shell command to execute (passed to /bin/zsh -c)"),
                "working_directory": .stringProperty(
                    "Working directory inside the active sandbox. Defaults to sandbox root (~/ or project root)."
                ),
                "timeout_seconds": .intProperty("Timeout in seconds (1–120, default 30)."),
                "allow_writes": .boolProperty(
                    """
                    Allow this command to modify files under the focus root (home or project). \
                    Defaults to false and requires write authorization.
                    """
                ),
                "allow_network": .boolProperty(
                    "Allow this command to access the network. Defaults to false and requires separate approval."
                ),
                "allow_protected_metadata_writes": .boolProperty(
                    "Allow writes to .git, .sage, or .agents. Defaults to false and requires separate approval."
                ),
                "sensitive_read_path": .stringProperty(
                    """
                    Sensitive directory to read for this command, such as ~/.ssh. Omit unless needed; \
                    access requires separate authorization.
                    """
                ),
            ],
            required: ["command"]
        )
    )

    func call(argumentsJSON: String) async throws -> String {
        let request = try ShellExecRequest.parse(argumentsJSON, policy: PathGuard.policy)
        try ShellCommandPolicy.validate(request.command)
        let ctx = ToolCtx(
            callID: "direct",
            toolName: definition.name,
            pathGuardPolicy: PathGuard.policy,
            workPlanKind: nil,
            approvalPolicy: .unlessTrusted,
            fileSystemPolicy: .sage(PathGuard.policy),
            readAllowlist: PathGuard.readAllowlist,
            extraReadableRoots: request.allowedSensitiveReadRoots
        )
        let attempt = SandboxAttempt.make(
            sandbox: SeatbeltSandbox.isAvailable ? .seatbelt : .none,
            sandboxRequested: true,
            bits: request.permissionBits,
            cwd: request.workingDirectory,
            ctx: ctx
        )
        return try await ShellRuntime().run(request, attempt: attempt, ctx: ctx)
    }
}

/// Shared denylist for `run_shell_command` and scheduled scripts.
nonisolated enum ShellCommandPolicy {
    private static let blockedPatterns: [String] = [
        "rm -rf /",
        "rm -rf /*",
        "rm -rf ~/",
        "rm -rf ~/*",
        "mkfs",
        "dd if=",
        ":(){:|:&};:",
        "chmod -R 777 /",
        "chown -R",
        "> /dev/sda",
        "shutdown",
        "reboot",
        "halt",
    ]

    private static let blockedCommands: [String] = [
        "sudo",
        "su",
        "doas",
    ]

    /// Throws when `command` uses a blocked token or dangerous pattern.
    static func validate(_ command: String) throws {
        let lowered = command.lowercased()
        let shellTokens = lowered.components(separatedBy: CharacterSet(charactersIn: ";|&\n"))
        for token in shellTokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            for blocked in blockedCommands {
                if trimmed == blocked
                    || trimmed.hasPrefix(blocked + " ")
                    || trimmed.hasPrefix(blocked + "\t") {
                    throw ToolError.operationFailed(
                        "Command blocked: '\(blocked)' is not allowed. Run commands as the current user only."
                    )
                }
            }
        }

        for pattern in blockedPatterns where lowered.contains(pattern) {
            throw ToolError.operationFailed(
                "Command blocked: contains dangerous pattern '\(pattern)'. This operation is not allowed."
            )
        }
    }
}
