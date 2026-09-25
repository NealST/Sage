//
//  operations.swift
//  CodexGitUtils
//
//  Port of codex-rs/git-utils/src/operations.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  Git invocations use `/usr/bin/git` via `Process` (`runGitSync`).
//

import Foundation

/// Encodes Git overrides without treating equals signs in keys as separators.
public func gitConfigOverrideEnv(
    _ overrides: [(String, String)]
) -> [(String, String)] {
    if overrides.isEmpty {
        return []
    }
    var environment = [("GIT_CONFIG_COUNT", String(overrides.count))]
    for (index, (key, value)) in overrides.enumerated() {
        environment.append(("GIT_CONFIG_KEY_\(index)", key))
        environment.append(("GIT_CONFIG_VALUE_\(index)", value))
    }
    return environment
}

func ensureGitRepository(_ path: String) throws {
    do {
        let output = try runGitForStdout(
            path,
            ["rev-parse", "--is-inside-work-tree"]
        )
        if output == "true" {
            return
        }
        throw GitToolingError.notAGitRepository(path: path)
    } catch let error as GitToolingError {
        if case .gitCommand(_, let status, _) = error, status == 128 {
            throw GitToolingError.notAGitRepository(path: path)
        }
        throw error
    }
}

func resolveHead(_ path: String) throws -> String? {
    do {
        return try runGitForStdout(path, ["rev-parse", "--verify", "HEAD"])
    } catch let error as GitToolingError {
        if case .gitCommand(_, let status, _) = error, status == 128 {
            return nil
        }
        throw error
    }
}

func resolveRepositoryRoot(_ path: String) throws -> String {
    try runGitForStdout(path, ["rev-parse", "--show-toplevel"])
}

func runGitForStatus(_ dir: String, _ args: [String], env: [String: String] = [:]) throws {
    _ = try runGit(dir, args, env: env)
}

func runGitForStdout(_ dir: String, _ args: [String], env: [String: String] = [:]) throws -> String {
    let run = try runGit(dir, args, env: env)
    guard let value = utf8String(run.stdout) else {
        throw GitToolingError.gitOutputUtf8(command: run.command)
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct GitRun {
    var command: String
    var stdout: Data
}

private func runGit(_ dir: String, _ args: [String], env: [String: String]) throws -> GitRun {
    var argsVec = ["-c", SAFE_BARE_REPOSITORY_CONFIG, "-c", "core.hooksPath=\(DISABLED_HOOKS_PATH)"]
    argsVec.append(contentsOf: args)
    let commandString = buildCommandString(argsVec)
    let output = try runGitSync(
        arguments: argsVec,
        currentDirectory: dir,
        extraEnvironment: env
    )
    if !output.success {
        let stderr = utf8Lossy(output.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        throw GitToolingError.gitCommand(
            command: commandString,
            status: output.status,
            stderr: stderr
        )
    }
    return GitRun(command: commandString, stdout: output.stdout)
}

private func buildCommandString(_ args: [String]) -> String {
    if args.isEmpty {
        return "git"
    }
    return "git \(args.joined(separator: " "))"
}
