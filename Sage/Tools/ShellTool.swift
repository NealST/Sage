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
            limited to working_directory and require authorization. \
            Network access is denied unless allow_network is explicitly true; requesting it is part of the \
            approval-scoped invocation. \
            Writes to .git, .sage, and .agents are denied unless allow_protected_metadata_writes is explicitly true. \
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
                    Allow this command to modify files under working_directory. Defaults to false \
                    and requires write authorization.
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

    private struct Args: Decodable {
        let command: String
        let workingDirectory: String?
        let timeoutSeconds: Int?
        let allowWrites: Bool?
        let allowNetwork: Bool?
        let allowProtectedMetadataWrites: Bool?
        let sensitiveReadPath: String?
    }

    private struct ExecutionRequest {
        let command: String
        let workingDirectory: URL
        let timeout: Int
        let allowWrites: Bool
        let allowNetwork: Bool
        let allowProtectedMetadataWrites: Bool
        let allowedSensitiveReadRoots: [URL]
    }

    private static let maxOutputBytes = 50_000

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let command = args.command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty else {
            throw ToolError.invalidArguments("Command cannot be empty.")
        }

        try ShellCommandPolicy.validate(command)

        // Resolve working directory (sandbox root when omitted)
        let workDir: URL
        if let dir = args.workingDirectory {
            workDir = try PathGuard.resolveAllowed(dir, access: .read)
        } else {
            workDir = PathGuard.policy.defaultWorkingDirectory
        }

        guard FileManager.default.fileExists(atPath: workDir.path) else {
            throw ToolError.operationFailed(
                """
                Working directory does not exist: \(args.workingDirectory ?? workDir.path). \
                Use create_directory first.
                """
            )
        }

        // Timeout: clamp to 1–120s
        let requestedTimeout = args.timeoutSeconds ?? 30
        let timeout = min(max(requestedTimeout, 1), 120)

        // Execute asynchronously
        let request = ExecutionRequest(
            command: command,
            workingDirectory: workDir,
            timeout: timeout,
            allowWrites: args.allowWrites ?? false,
            allowNetwork: args.allowNetwork ?? false,
            allowProtectedMetadataWrites: args.allowProtectedMetadataWrites ?? false,
            allowedSensitiveReadRoots: try allowedSensitiveRoots(for: args.sensitiveReadPath)
        )
        let (exitCode, output) = try await executeCommand(request)

        // Format result
        let truncated = output.count > Self.maxOutputBytes
        let displayOutput: String
        if truncated {
            displayOutput = String(output.prefix(Self.maxOutputBytes))
                + "\n… (output truncated at \(Self.maxOutputBytes) bytes)"
        } else {
            displayOutput = output
        }

        if exitCode == 0 {
            return displayOutput.isEmpty
                ? "[exit 0] (no output)"
                : "[exit 0]\n\(displayOutput)"
        }
        return "[exit \(exitCode)]\n\(displayOutput)"
    }

    private func executeCommand(_ request: ExecutionRequest) async throws -> (Int32, String) {
        let configuration = ExecutionSandboxConfiguration.shell(
            policy: PathGuard.policy,
            readAllowlist: PathGuard.readAllowlist,
            writeRoot: request.workingDirectory,
            allowsWrites: request.allowWrites,
            allowsNetwork: request.allowNetwork,
            allowsProtectedMetadataWrites: request.allowProtectedMetadataWrites,
            allowedSensitiveReadRoots: request.allowedSensitiveReadRoots
        )
        let invocation = ExecutionSandbox.wrap(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-f", "-c", request.command],
            configuration: configuration,
            auditComponent: "interactive_shell"
        )
        let result = try await ProcessRunner.run(
            executable: invocation.executable,
            arguments: invocation.arguments,
            currentDirectory: request.workingDirectory,
            timeout: .seconds(request.timeout)
        )
        if result.timedOut {
            return (
                result.exitCode,
                result.output + "\n… (command timed out after \(request.timeout)s)"
            )
        }
        return (result.exitCode, result.output)
    }

    private func allowedSensitiveRoots(for rawPath: String?) throws -> [URL] {
        guard let rawPath else { return [] }
        let url = try PathGuard.resolveAllowed(rawPath, access: .read)
        guard let root = SensitiveResourcePolicy.containingRoot(for: url) else {
            throw ToolError.invalidArguments(
                "sensitive_read_path must identify a protected sensitive directory."
            )
        }
        return [root]
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
