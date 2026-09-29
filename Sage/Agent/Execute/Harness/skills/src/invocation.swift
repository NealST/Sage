//
//  invocation.swift
//  CodexSkills
//
//  Port of codex-rs/skills/src/invocation.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: adapted
//
//  `shlex::split` is `posixShlexSplit`. Windows PowerShell tokenization is
//  unused on macOS. `parse_command_impl` is the public CodexShellCommand API.
//

import CodexProtocol
import CodexShellCommand
import CodexUtils
import Foundation

/// A skill document read or script execution identified in a shell command.
public enum ImplicitSkillAccess: Equatable, Sendable {
    case document(PathUri)
    case script(PathUri)
}

/// Provides the indexed skill lookups used to recognize implicit invocations.
public protocol ImplicitSkillLookup {
    func implicitSkillForScriptsDir(_ path: AbsolutePathBuf) -> SkillMetadata?
    func implicitSkillForDocPath(_ path: AbsolutePathBuf) -> SkillMetadata?
}

public func detectImplicitSkillInvocationForCommand(
    outcome: any ImplicitSkillLookup,
    command: String,
    workdir: AbsolutePathBuf
) -> SkillMetadata? {
    let workdir = canonicalizeIfExists(workdir)
    let tokens = tokenizeCommand(command)
    if let candidate = detectSkillScriptRun(outcome, tokens: tokens, workdir: workdir) {
        return candidate
    }
    return detectSkillDocRead(outcome, tokens: tokens, workdir: workdir)
}

/// Resolves statically recognizable skill accesses without consulting the host filesystem.
public func implicitSkillAccessesForCommand(
    command: String,
    workdir: PathUri
) -> [ImplicitSkillAccess] {
    let tokens = tokenizeCommand(command)
    var accesses: [ImplicitSkillAccess] = []
    if let script = scriptRunToken(tokens), let path = try? workdir.join(script) {
        accesses.append(.script(path))
    }
    for parsed in parseCommandImpl(tokens) {
        if case .read(_, _, let path) = parsed, let joined = try? workdir.join(path) {
            accesses.append(.document(joined))
        }
    }
    return accesses
}

func tokenizeCommand(_ command: String) -> [String] {
    posixShlexSplit(command) ?? command.split { $0.isWhitespace }.map(String.init)
}

func scriptRunToken(_ tokens: [String]) -> String? {
    let runners: Set<String> = [
        "python", "python3", "bash", "zsh", "sh", "node", "deno", "ruby", "perl", "pwsh",
    ]
    let scriptExtensions = [".py", ".sh", ".js", ".ts", ".rb", ".pl", ".ps1"]
    guard let runnerToken = tokens.first else { return nil }
    var runner = commandBasename(runnerToken).lowercased()
    if runner.hasSuffix(".exe") {
        runner = String(runner.dropLast(4))
    }
    guard runners.contains(runner) else { return nil }

    var scriptToken: String?
    for token in tokens.dropFirst() {
        if token == "--" || token.hasPrefix("-") { continue }
        scriptToken = token
        break
    }
    guard let scriptToken else { return nil }
    let lower = scriptToken.lowercased()
    if scriptExtensions.contains(where: { lower.hasSuffix($0) }) {
        return scriptToken
    }
    return nil
}

func detectSkillScriptRun(
    _ outcome: any ImplicitSkillLookup,
    tokens: [String],
    workdir: AbsolutePathBuf
) -> SkillMetadata? {
    guard let scriptToken = scriptRunToken(tokens) else { return nil }
    let scriptPath = canonicalizeIfExists(workdir.join(scriptToken))
    for path in scriptPath.ancestors() {
        if let candidate = outcome.implicitSkillForScriptsDir(path) {
            return candidate
        }
    }
    return nil
}

func detectSkillDocRead(
    _ outcome: any ImplicitSkillLookup,
    tokens: [String],
    workdir: AbsolutePathBuf
) -> SkillMetadata? {
    for command in parseCommandImpl(tokens) {
        if case .read(_, _, let path) = command {
            let candidatePath = canonicalizeIfExists(workdir.join(path))
            if let candidate = outcome.implicitSkillForDocPath(candidatePath) {
                return candidate
            }
        }
    }
    return nil
}

func commandBasename(_ command: String) -> String {
    command.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? command
}

func canonicalizeIfExists(_ path: AbsolutePathBuf) -> AbsolutePathBuf {
    (try? path.canonicalize()) ?? path
}
