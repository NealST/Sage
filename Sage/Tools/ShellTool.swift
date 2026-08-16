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
            Defaults to the sandbox root. Default timeout is 30s (max 120s). \
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
            ],
            required: ["command"]
        )
    )

    private struct Args: Decodable {
        let command: String
        let workingDirectory: String?
        let timeoutSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case command
            case workingDirectory = "working_directory"
            case timeoutSeconds = "timeout_seconds"
        }
    }

    private static let maxOutputBytes = 50_000

    /// Commands that are too dangerous to execute.
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

    /// Keywords that require elevated privileges — block if they appear as a command token.
    private static let blockedCommands: [String] = [
        "sudo",
        "su",
        "doas",
    ]

    func call(argumentsJSON: String) async throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let command = args.command.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !command.isEmpty else {
            throw ToolError.invalidArguments("Command cannot be empty.")
        }

        // Safety checks
        try validateCommand(command)

        // Resolve working directory (sandbox root when omitted)
        let workDir: URL
        if let dir = args.workingDirectory {
            workDir = try PathGuard.resolveAllowed(dir)
        } else {
            workDir = PathGuard.policy.defaultWorkingDirectory
        }

        guard FileManager.default.fileExists(atPath: workDir.path) else {
            throw ToolError.operationFailed(
                "Working directory does not exist: \(args.workingDirectory ?? workDir.path). Use create_directory first."
            )
        }

        // Timeout: clamp to 1–120s
        let requestedTimeout = args.timeoutSeconds ?? 30
        let timeout = min(max(requestedTimeout, 1), 120)

        // Execute asynchronously
        let (exitCode, output) = try await executeCommand(
            command: command,
            workingDirectory: workDir,
            timeout: timeout
        )

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
        } else {
            return "[exit \(exitCode)]\n\(displayOutput)"
        }
    }

    private func validateCommand(_ command: String) throws {
        let lowered = command.lowercased()

        // Check for privilege escalation commands anywhere in the pipeline
        // Split on shell operators to find individual commands
        let shellTokens = lowered.components(separatedBy: CharacterSet(charactersIn: ";|&\n"))
        for token in shellTokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            for blocked in Self.blockedCommands {
                if trimmed == blocked
                    || trimmed.hasPrefix(blocked + " ")
                    || trimmed.hasPrefix(blocked + "\t")
                {
                    throw ToolError.operationFailed(
                        "Command blocked: '\(blocked)' is not allowed. Run commands as the current user only."
                    )
                }
            }
        }

        for pattern in Self.blockedPatterns {
            if lowered.contains(pattern) {
                throw ToolError.operationFailed(
                    "Command blocked: contains dangerous pattern '\(pattern)'. This operation is not allowed."
                )
            }
        }
    }

    private func executeCommand(
        command: String,
        workingDirectory: URL,
        timeout: Int
    ) async throws -> (Int32, String) {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-c", command],
            currentDirectory: workingDirectory,
            timeout: .seconds(timeout)
        )
        if result.timedOut {
            return (
                result.exitCode,
                result.output + "\n… (command timed out after \(timeout)s)"
            )
        }
        return (result.exitCode, result.output)
    }
}
