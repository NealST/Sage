//
//  git_process.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/git_process.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Tokio `Command` + process-group kill (`codex-utils-pty`) is Foundation
//  `Process` launching `/usr/bin/git`. Timeouts call `terminate()`. Windows
//  job-object containment is omitted (platform: macOS).
//

import CodexProtocol
import Foundation

struct GitProcessOutput: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var success: Bool { status == 0 }
}

func runGitCommandWithTimeoutOutput(
    arguments: [String],
    currentDirectory: String,
    extraEnvironment: [String: String] = [:],
    timeout: TimeInterval
) async -> GitProcessOutput? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            process.standardInput = FileHandle.nullDevice

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            var environment = ProcessInfo.processInfo.environment
            scrubNonInheritableEnvVars(&environment)
            for (key, value) in extraEnvironment {
                environment[key] = value
            }
            process.environment = environment

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            let group = DispatchGroup()
            group.enter()
            process.terminationHandler = { _ in group.leave() }
            let waitResult = group.wait(timeout: .now() + timeout)
            if waitResult == .timedOut {
                process.terminate()
                _ = group.wait(timeout: .now() + 2)
                continuation.resume(returning: nil)
                return
            }

            continuation.resume(
                returning: GitProcessOutput(
                    status: process.terminationStatus,
                    stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
                    stderr: stderr.fileHandleForReading.readDataToEndOfFile()
                )
            )
        }
    }
}

func runGitSync(
    arguments: [String],
    currentDirectory: String,
    extraEnvironment: [String: String] = [:]
) throws -> GitProcessOutput {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
    process.standardInput = FileHandle.nullDevice

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    var environment = ProcessInfo.processInfo.environment
    scrubNonInheritableEnvVars(&environment)
    for (key, value) in extraEnvironment {
        environment[key] = value
    }
    process.environment = environment

    try process.run()
    process.waitUntilExit()
    return GitProcessOutput(
        status: process.terminationStatus,
        stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
        stderr: stderr.fileHandleForReading.readDataToEndOfFile()
    )
}

func utf8String(_ data: Data) -> String? {
    String(data: data, encoding: .utf8)
}

func utf8Lossy(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
}
