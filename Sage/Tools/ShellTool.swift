//
//  ShellTool.swift
//  Sage
//

import Foundation

struct RunShellCommandTool: AgentTool {
    let definition = ToolDefinition(
        name: "run_shell_command",
        description: """
            Execute a shell command via /bin/zsh -c and return its output (stdout + stderr combined). \
            Working directory must be under ~/. Default timeout is 30s (max 120s). \
            Output is capped at 50KB. Result format: "[exit N]\\n<output>". \
            Dangerous commands (rm -rf /, sudo, etc.) are blocked. \
            Use for: git, grep, find, python, node, brew, make, and other CLI tools.
            """,
        parameters: .schemaObject(
            properties: [
                "command": .stringProperty("Shell command to execute (passed to /bin/zsh -c)"),
                "working_directory": .stringProperty("Working directory (must be under ~/). Defaults to ~."),
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

        // Resolve working directory
        let workDir: URL
        if let dir = args.workingDirectory {
            workDir = try PathGuard.resolveAllowed(dir)
        } else {
            workDir = FileManager.default.homeDirectoryForCurrentUser
        }

        guard FileManager.default.fileExists(atPath: workDir.path) else {
            throw ToolError.operationFailed(
                "Working directory does not exist: \(args.workingDirectory ?? "~"). Use create_directory first."
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = workingDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Read pipe data asynchronously to avoid deadlock when output exceeds pipe buffer.
        // We must start reading BEFORE the process fills the buffer.
        let collectedData = UncheckedSendable(LockedBuffer())

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                collectedData.value.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw ToolError.operationFailed(
                "Failed to start command: \(error.localizedDescription)"
            )
        }

        // Wait for termination with timeout using structured concurrency.
        // We use process.waitUntilExit() on a detached thread to avoid the race condition
        // where the process terminates before terminationHandler is set.
        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async {
                        process.waitUntilExit()
                        cont.resume()
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                return true
            }

            let first = await group.next()!
            group.cancelAll()
            return first
        }

        if timedOut {
            process.terminate()
            // Give process a moment to exit after SIGTERM
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Drain any remaining data in the pipe
        pipe.fileHandleForReading.readabilityHandler = nil
        let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            collectedData.value.append(remaining)
        }

        let data = collectedData.value.data
        let output = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? "(binary output, \(data.count) bytes)"

        let exitCode = process.terminationStatus
        if timedOut {
            return (exitCode, output + "\n… (command timed out after \(timeout)s)")
        }
        return (exitCode, output)
    }
}

// MARK: - Helpers

/// Thread-safe mutable data buffer for collecting pipe output.
private final class LockedBuffer: @unchecked Sendable {
    private var _data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        _data.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }
}

/// Wrapper to pass non-Sendable references across concurrency boundaries when safety is ensured externally.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
