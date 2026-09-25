//
//  denial.swift
//  CodexSandboxing
//
//  Port of codex-rs/sandboxing/src/denial.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Side-effect-free sandbox-denial heuristics from exec output.
//

import CodexProtocol

public func isLikelySandboxDenied(
    sandboxType: SandboxType,
    execOutput: ExecToolCallOutput
) -> Bool {
    if sandboxType == .none || execOutput.exitCode == 0 {
        return false
    }
    if isLikelyExecutorManagedSandboxDenied(execOutput) {
        return true
    }
    let quickReject: [Int32] = [2, 126, 127]
    if quickReject.contains(execOutput.exitCode) {
        return false
    }
    let exitCodeSignalBase: Int32 = 128
    let sigsys: Int32 = 12
    if sandboxType == .linuxSeccomp
        && execOutput.exitCode == exitCodeSignalBase + sigsys {
        return true
    }
    return false
}

public func isLikelyExecutorManagedSandboxDenied(_ execOutput: ExecToolCallOutput) -> Bool {
    if execOutput.exitCode == 0 { return false }
    let keywords = [
        "operation not permitted",
        "permission denied",
        "read-only file system",
        "seccomp",
        "sandbox",
        "landlock",
        "failed to write file",
    ]
    return [execOutput.stderr.text, execOutput.stdout.text, execOutput.aggregatedOutput.text]
        .contains { section in
            let lower = section.lowercased()
            return keywords.contains { lower.contains($0) }
        }
}
